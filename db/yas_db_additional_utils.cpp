//
//  yas_db_additional_utils.cpp
//

#include "yas_db_additional_utils.h"
#include "yas_result.h"
#include "yas_db_sql_utils.h"
#include "yas_stl_utils.h"
#include "yas_db_model.h"
#include "yas_unless.h"
#include "yas_db_value.h"
#include "yas_db_object.h"
#include "yas_db_entity.h"
#include "yas_db_relation.h"
#include "yas_db_database.h"
#include "yas_db_info.h"
#include "yas_version.h"
#include "yas_db_attribute.h"
#include "yas_db_index.h"

using namespace yas;

namespace yas {
namespace db {
    // 指定したsave_id以前で、object_idが同じなら最後のものをselectする条件
    std::string last_where_exprs(std::string const &table, std::string const &where_exprs,
                                 db::value const &last_save_id, bool const include_removed) {
        std::vector<std::string> components;

        if (last_save_id) {
            components.emplace_back(db::expr(db::save_id_field, "<=", last_save_id.sql()));
        }

        if (where_exprs.size() > 0) {
            components.push_back(where_exprs);
        }

        db::select_option option{.table = table,
                                 .fields = {"MAX(" + db::rowid_field + ")"},
                                 .where_exprs = joined(components, " AND "),
                                 .group_by = db::object_id_field};
        std::string result_exprs = db::in_expr(db::rowid_field, option);

        if (!include_removed) {
            static std::string const exclude_removed_expr = db::action_field + " != '" + db::remove_action + "'";
            result_exprs = joined({result_exprs, exclude_removed_expr}, " AND ");
        }

        return result_exprs;
    }

    // 単独の関連の関連先のidの配列をDBから取得する
    db::value_vector_result_t select_relation_target_ids(db::database &db, std::string const &rel_table,
                                                         db::value const &save_id, db::value const &src_obj_id) {
        std::string where_exprs =
            joined({db::equal_field_expr(db::save_id_field), db::equal_field_expr(db::src_obj_id_field)}, " and ");
        db::select_option option{.table = rel_table,
                                 .where_exprs = std::move(where_exprs),
                                 .arguments = {{db::save_id_field, save_id}, {db::src_obj_id_field, src_obj_id}}};

        if (auto select_result = db::select(db, option)) {
            auto const &result_rels = select_result.value();
            db::value_vector_t rel_tgts;
            rel_tgts.reserve(result_rels.size());
            for (auto const &result_rel : result_rels) {
                rel_tgts.push_back(result_rel.at(db::tgt_obj_id_field));
            }
            return db::value_vector_result_t{std::move(rel_tgts)};
        } else {
            return db::value_vector_result_t{std::move(select_result.error())};
        }
    }

    // 単独のオブジェクトの全ての関連の関連先のidの配列をDBから取得する
    db::value_vector_map_result_t select_relation_data(db::database &db, db::relation_map_t const &rel_models,
                                                       db::value const &save_id, db::value const &src_obj_id) {
        db::value_vector_map_t relations;

        for (auto const &rel_model_pair : rel_models) {
            auto const &rel_name = rel_model_pair.first;
            auto const &rel_table = rel_model_pair.second.table_name;

            if (auto select_result = db::select_relation_target_ids(db, rel_table, save_id, src_obj_id)) {
                relations.emplace(rel_name, std::move(select_result.value()));
            } else {
                return db::value_vector_map_result_t{std::move(select_result.error())};
            }
        }

        return db::value_vector_map_result_t{std::move(relations)};
    }
}
}

db::manager_result_t db::migrate_db_if_needed(db::database &db, db::model const &model) {
    // infoからバージョンを取得。1つしかデータが無いこと前提
    if (auto select_result = db::select_db_info(db)) {
        // infoを現在のバージョンで上書き
        if (auto update_result = db::update_version(db, model.version())) {
            db::info const &info = select_result.value();
            if (model.version() <= info.version()) {
                // モデルのバージョンがデータベースのバージョンがより低ければマイグレーションを行わない
                return db::manager_result_t{nullptr};
            }
        } else {
            return update_result;
        }
    } else {
        return db::manager_result_t{std::move(select_result.error())};
    }

    // マイグレーションが必要な場合
    for (auto const &entity_pair : model.entities()) {
        auto const &entity_name = entity_pair.first;
        auto const &entity = entity_pair.second;

        if (db::table_exists(db, entity_name)) {
            // エンティティのテーブルがすでに存在している場合
            for (auto const &attr_pair : entity.all_attributes) {
                if (!db::column_exists(db, attr_pair.first, entity_name)) {
                    // テーブルにカラムが存在しなければalter tableを実行する
                    auto const &attr = attr_pair.second;
                    if (auto ul = unless(db.execute_update(alter_table_sql(entity_name, attr.sql())))) {
                        return db::make_error_result(db::manager_error_type::alter_entity_table_failed,
                                                     std::move(ul.value.error()));
                    }
                }
            }
        } else {
            // エンティティのテーブルが存在していない場合
            // テーブルを作成する
            if (auto ul = unless(db.execute_update(entity.sql_for_create()))) {
                return db::make_error_result(db::manager_error_type::create_entity_table_failed,
                                             std::move(ul.value.error()));
            }
        }

        // 関連のテーブルを作成する
        for (auto &rel_pair : entity.relations) {
            if (auto ul = unless(db.execute_update(rel_pair.second.sql_for_create()))) {
                return db::make_error_result(db::manager_error_type::create_relation_table_failed,
                                             std::move(ul.value.error()));
            }
        }
    }

    // インデックスのテーブルを作成する
    for (auto const &index_pair : model.indices()) {
        if (!db::index_exists(db, index_pair.first)) {
            auto &index = index_pair.second;
            if (auto ul = unless(db.execute_update(index.sql_for_create()))) {
                return db::make_error_result(db::manager_error_type::create_index_failed, std::move(ul.value.error()));
            }
        }
    }

    return db::manager_result_t{nullptr};
}

db::manager_result_t db::create_info_and_tables(db::database &db, db::model const &model) {
    // infoテーブルをデータベース上に作成
    if (auto ul = unless(db::create_db_info(db, model.version()))) {
        return std::move(ul.value);
    }

    // 全てのエンティティと関連のテーブルをデータベース上に作成する
    auto const &entities = model.entities();
    for (auto &entity_pair : entities) {
        auto &entity = entity_pair.second;
        if (auto ul = unless(db.execute_update(entity.sql_for_create()))) {
            return db::make_error_result(db::manager_error_type::create_entity_table_failed,
                                         std::move(ul.value.error()));
        }

        for (auto &rel_pair : entity.relations) {
            if (auto ul = unless(db.execute_update(rel_pair.second.sql_for_create()))) {
                return db::make_error_result(db::manager_error_type::create_relation_table_failed,
                                             std::move(ul.value.error()));
            }
        }
    }

    // 全てのインデックスをデータベース上に作成する
    for (auto const &index_pair : model.indices()) {
        auto &index = index_pair.second;
        if (auto ul = unless(db.execute_update(index.sql_for_create()))) {
            return db::make_error_result(db::manager_error_type::create_index_failed, std::move(ul.value.error()));
        }
    }

    return db::manager_result_t{nullptr};
}

db::manager_info_result_t db::clear_db(db::database &db, db::model const &model) {
    // トランザクション開始
    for (auto const &entity_pair : model.entities()) {
        auto const &entity = entity_pair.second;
        auto const &entity_table_name = entity.name;

        // エンティティのテーブルのデータを全てデータベースから削除
        if (auto ul = unless(db.execute_update(db::delete_sql(entity_table_name)))) {
            return db::manager_info_result_t{
                db::manager_error{db::manager_error_type::delete_failed, std::move(ul.value.error())}};
        }

        for (auto const &rel_pair : entity.relations) {
            auto const rel_table_name = rel_pair.second.table_name;

            // 関連のテーブルのデータを全てデータベースから削除
            if (auto ul = unless(db.execute_update(db::delete_sql(rel_table_name)))) {
                return db::manager_info_result_t{
                    db::manager_error{db::manager_error_type::delete_failed, std::move(ul.value.error())}};
            }
        }
    }

    // infoをクリア。セーブIDを0にする
    db::value const zero_value{db::integer::type{0}};
    if (auto update_result = db::update_db_info(db, zero_value, zero_value)) {
        return db::manager_info_result_t{std::move(update_result.value())};
    } else {
        return db::manager_info_result_t{std::move(update_result.error())};
    }
}

db::select_result_t db::select_last(db::database const &db, db::select_option option, db::value const &save_id,
                                    bool const include_removed) {
    option.where_exprs = db::last_where_exprs(option.table, option.where_exprs, save_id, include_removed);
    return db::select(db, option);
}

db::select_result_t db::select_undo(db::database const &db, std::string const &table,
                                    db::integer::type const revert_save_id, db::integer::type const current_save_id) {
    // リバート先のセーブIDはカレントより小さくないといけない
    if (current_save_id <= revert_save_id) {
        throw "revert_save_id greater than or equal to current_save_id";
    }

    // アンドゥで戻そうとしているデータ（リバート先からカレントまでの間）のobject_idの集合を取得する
    std::string const reverting_where = joined({db::expr(db::save_id_field, "<=", std::to_string(current_save_id)),
                                                db::expr(db::save_id_field, ">", std::to_string(revert_save_id))},
                                               " AND ");
    db::select_option reverting_option{
        .table = table, .fields = {db::object_id_field}, .distinct = true, .where_exprs = reverting_where};
    std::string const reverting_obj_ids_expr = db::in_expr(db::object_id_field, reverting_option);

    // 戻そうとしているobject_idと一致し、リバート時点より前のデータの中で最後のもののrowidの集合を取得する
    // つまり、アンドゥ時点より前に挿入されて、アンドゥ時点より後に変更があったデータを取得する
    std::string const reverted_last_where =
        joined({reverting_obj_ids_expr, db::expr(db::save_id_field, "<=", std::to_string(revert_save_id))}, " AND ");
    db::select_option reverted_last_option{.table = table,
                                           .fields = {"MAX(" + db::rowid_field + ")"},
                                           .where_exprs = reverted_last_where,
                                           .group_by = db::object_id_field};
    std::string const reverted_last_rowids_where = db::in_expr(db::rowid_field, reverted_last_option);
    db::select_option option{.table = table,
                             .where_exprs = reverted_last_rowids_where,
                             .field_orders = {{db::object_id_field, db::order::ascending}}};

    auto result = db::select(db, option);
    if (!result) {
        return db::select_result_t{std::move(result.error())};
    }

    // アンドゥで戻そうとしている範囲のデータの中で、insertのobject_idの集合をobject_idのみで取得
    // つまり、アンドゥ時点より後に挿入されたデータを空にするために取得する
    db::select_option empty_option{
        .table = table,
        .fields = {db::object_id_field},
        .where_exprs = joined(
            {db::expr(db::save_id_field, "<=", std::to_string(current_save_id)),
             db::expr(db::save_id_field, ">", std::to_string(revert_save_id)), db::equal_field_expr(db::action_field)},
            " AND "),
        .arguments = {{db::action_field, db::insert_action_value()}},
        .field_orders = {{db::object_id_field, db::order::ascending}}};

    auto empty_result = db::select(db, empty_option);
    if (!empty_result) {
        return db::select_result_t{std::move(empty_result.error())};
    }

    // キャッシュを上書きするためのデータを返す
    return db::select_result_t{connect(std::move(result.value()), std::move(empty_result.value()))};
}

db::select_result_t db::select_redo(db::database const &db, std::string const &table,
                                    db::integer::type const revert_save_id, db::integer::type const current_save_id) {
    // リバート先のセーブIDはカレントより後でないといけない
    if (revert_save_id <= current_save_id) {
        throw "current_save_id greater than or equal to revert_save_id";
    }

    // カレントからリドゥ時点の範囲で変更のあったデータを取得して返す
    db::select_option option{.table = table,
                             .where_exprs = db::expr(db::save_id_field, ">", std::to_string(current_save_id)),
                             .field_orders = {{db::object_id_field, db::order::ascending}}};

    return db::select_last(db, std::move(option), db::value{revert_save_id}, true);
}

db::select_result_t db::select_revert(db::database const &db, std::string const &table,
                                      db::integer::type const revert_save_id, db::integer::type const current_save_id) {
    // リバート先のセーブIDによってアンドゥとリドゥに分岐する
    if (revert_save_id < current_save_id) {
        return db::select_undo(db, table, revert_save_id, current_save_id);
    } else if (current_save_id < revert_save_id) {
        return db::select_redo(db, table, revert_save_id, current_save_id);
    }

    return db::select_result_t{db::value_map_vector_t{}};
}

db::select_result_t db::select_relation_removed(db::database const &db, std::string const &entity_table,
                                                std::string const &rel_table, db::value_vector_t const &tgt_obj_ids) {
    // 最後のオブジェクトのpk_idを取得するsql
    auto const last_exprs = db::last_where_exprs(entity_table, "", nullptr, false);
    db::select_option const last_option{.table = entity_table, .fields = {db::pk_id_field}, .where_exprs = last_exprs};

    // 最後のオブジェクトの中でtgt_obj_idsに一致する関連のsrc_pk_idを取得するsql
    std::string const tgt_where_exprs = joined(
        {db::in_expr(db::src_pk_id_field, last_option), db::in_expr(db::tgt_obj_id_field, tgt_obj_ids)}, " AND ");
    db::select_option src_pk_option{
        .table = rel_table, .fields = {db::src_pk_id_field}, .where_exprs = tgt_where_exprs};

    // これまでの条件に一致しつつ、アクションがremoveでないアトリビュートを取得する
    std::string const where_exprs =
        joined({db::field_expr(db::action_field, "!="), db::in_expr(db::pk_id_field, src_pk_option)}, " AND ");
    db::select_option option{.table = entity_table,
                             .where_exprs = where_exprs,
                             .arguments = {{db::action_field, db::remove_action_value()}}};
    return db::select(db, option);
}

db::manager_info_result_t db::select_db_info(db::database const &db) {
    if (auto select_result = db::select_single(db, db::select_option{.table = db::info_table})) {
        auto const &values = select_result.value();
        if (values.count(db::version_field) == 0) {
            return db::manager_info_result_t{db::manager_error{db::manager_error_type::version_not_found}};
        }
        if (values.count(db::current_save_id_field) == 0) {
            return db::manager_info_result_t{db::manager_error{db::manager_error_type::save_id_not_found}};
        }
        if (values.count(db::last_save_id_field) == 0) {
            return db::manager_info_result_t{db::manager_error{db::manager_error_type::save_id_not_found}};
        }

        return db::manager_info_result_t{db::info{select_result.value()}};
    } else {
        return db::manager_info_result_t{db::manager_error{db::manager_error_type::select_info_failed}};
    }
}

db::manager_result_t db::create_db_info(db::database &db, yas::version const &version) {
    // infoテーブルをデータベース上に作成
    if (auto ul = unless(db.execute_update(db::info::sql_for_create()))) {
        return db::make_error_result(db::manager_error_type::create_info_table_failed, std::move(ul.value.error()));
    }

    db::value const zero_value{db::integer::type{0}};
    db::value_vector_t const args{db::value{version.str()}, zero_value, zero_value};

    // infoデータを挿入。セーブIDは0
    if (auto ul = unless(db.execute_update(db::info::sql_for_insert(), args))) {
        return db::make_error_result(db::manager_error_type::insert_info_failed, std::move(ul.value.error()));
    }

    return db::manager_result_t{nullptr};
}

db::manager_info_result_t db::update_db_info(db::database &db, db::value const &cur_save_id,
                                             db::value const &last_save_id) {
    db::value_vector_t const params{cur_save_id, last_save_id};
    if (auto update_result = db.execute_update(db::info::sql_for_update_save_ids(), params)) {
        if (auto select_result = db::select_db_info(db)) {
            return db::manager_info_result_t{std::move(select_result.value())};
        } else {
            return db::manager_info_result_t{std::move(select_result.error())};
        }
    } else {
        return db::manager_info_result_t{
            db::manager_error{db::manager_error_type::update_info_failed, std::move(update_result.error())}};
    }
}

db::manager_info_result_t db::update_current_save_id(db::database &db, db::value const &cur_save_id) {
    db::value_vector_t const params{cur_save_id};
    if (auto update_result = db.execute_update(db::info::sql_for_update_current_save_id(), params)) {
        if (auto select_result = db::select_db_info(db)) {
            return db::manager_info_result_t{std::move(select_result.value())};
        } else {
            return db::manager_info_result_t{std::move(select_result.error())};
        }
    } else {
        return db::manager_info_result_t{
            db::manager_error{db::manager_error_type::update_info_failed, std::move(update_result.error())}};
    }
}

db::manager_result_t db::update_version(db::database &db, yas::version const &version) {
    if (auto update_result = db.execute_update(db::info::sql_for_update_version(), {db::value{version.str()}})) {
        return db::manager_result_t{nullptr};
    } else {
        return db::make_error_result(db::manager_error_type::update_info_failed, std::move(update_result.error()));
    }
}

db::update_result_t db::purge(db::database &db, std::string const &table) {
    db::select_option const option{
        .table = table, .fields = {"MAX(" + db::pk_id_field + ")"}, .group_by = db::object_id_field};
    std::string const in_expr = db::in_expr("NOT " + db::pk_id_field, option);
    return db.execute_update(db::delete_sql(table, in_expr));
}

db::update_result_t db::purge_relation(database &db, std::string const &table, std::string const &src_table) {
    db::select_option const option{.table = src_table, .fields = {db::pk_id_field}};
    std::string const in_expr = db::in_expr("NOT " + db::src_pk_id_field, option);
    return db.execute_update(db::delete_sql(table, in_expr));
}

db::manager_result_t db::make_error_result(db::manager_error_type const &error_type, db::error db_error) {
    return db::manager_result_t{db::manager_error{error_type, std::move(db_error)}};
}

// 単独のエンティティでオブジェクトのアトリビュートの値を元に関連の値をデータベースから取得してobject_dataのvectorを生成する
db::object_data_vector_result_t db::make_entity_object_datas(db::database &db, std::string const &entity_name,
                                                             db::relation_map_t const &rel_models,
                                                             db::value_map_vector_t const &entity_attrs) {
    db::object_data_vector_t entity_datas;
    entity_datas.reserve(entity_attrs.size());

    for (db::value_map_t attrs : entity_attrs) {
        db::value_vector_map_t rels;

        if (attrs.count(db::save_id_field) > 0) {
            auto const &save_id = attrs.at(db::save_id_field);
            auto const &src_obj_id = attrs.at(db::object_id_field);

            if (auto rel_data_result = db::select_relation_data(db, rel_models, save_id, src_obj_id)) {
                rels = std::move(rel_data_result.value());
            } else {
                return db::object_data_vector_result_t{std::move(rel_data_result.error())};
            }
        }

        entity_datas.emplace_back(db::object_data{std::move(attrs), std::move(rels)});
    }

    return db::object_data_vector_result_t{std::move(entity_datas)};
}

// 指定したsave_idより大きいsave_idのデータを、全てのエンティティに対してデータベース上から削除する
db::manager_result_t db::delete_next_to_last(db::database &db, db::model const &model, db::value const &save_id) {
    auto const &entity_models = model.entities();
    auto const delete_exprs = expr(db::save_id_field, ">", to_string(save_id));

    for (auto const &entity_pair : entity_models) {
        auto const &entity_name = entity_pair.first;

        if (auto delete_result = db.execute_update(db::delete_sql(entity_name, delete_exprs))) {
            for (auto const &rel_pair : entity_pair.second.relations) {
                auto const table = rel_pair.second.table_name;

                if (auto ul = unless(db.execute_update(db::delete_sql(table, delete_exprs)))) {
                    return db::make_error_result(db::manager_error_type::delete_failed, std::move(ul.value.error()));
                }
            }
        } else {
            return db::make_error_result(db::manager_error_type::delete_failed, std::move(delete_result.error()));
        }
    }

    return db::manager_result_t{nullptr};
}

db::manager_result_t db::insert_relations(db::database &db, db::relation const &rel_model, db::value const &src_pk_id,
                                          db::value const &src_obj_id, db::value_vector_t const &rel_tgt_obj_ids,
                                          db::value const &save_id) {
    auto const &rel_insert_sql = rel_model.sql_for_insert();
    auto src_pk_id_pair = std::make_pair(db::src_pk_id_field, src_pk_id);
    auto src_obj_id_pair = std::make_pair(db::src_obj_id_field, src_obj_id);
    auto save_id_pair = std::make_pair(db::save_id_field, save_id);

    for (auto const &rel_tgt_obj_id : rel_tgt_obj_ids) {
        auto tgt_obj_id_pair = std::make_pair(db::tgt_obj_id_field, rel_tgt_obj_id);

        db::value_map_t args{src_pk_id_pair, src_obj_id_pair, std::move(tgt_obj_id_pair), save_id_pair};
        if (auto ul = unless(db.execute_update(rel_insert_sql, std::move(args)))) {
            return db::make_error_result(db::manager_error_type::insert_relation_failed, std::move(ul.value.error()));
        }
    }
    return db::manager_result_t{nullptr};
}

// 複数のエンティティのobject_dataのvectorから、const_objectのvectorを生成する
db::const_object_vector_map_t db::to_const_vector_objects(db::model const &model,
                                                          db::object_data_vector_map_t const &datas) {
    db::const_object_vector_map_t objects;
    for (auto const &entity_pair : datas) {
        auto const &entity_name = entity_pair.first;
        auto const &entity_datas = entity_pair.second;

        db::const_object_vector_t entity_objects;
        entity_objects.reserve(entity_datas.size());

        for (auto const &data : entity_datas) {
            if (db::const_object obj{model.entity(entity_name), data}) {
                entity_objects.emplace_back(std::move(obj));
            }
        }

        objects.emplace(entity_name, std::move(entity_objects));
    }
    return objects;
}

// 複数のエンティティのobject_dataのvectorから、object_idをキーとしたconst_objectのmapを生成する
db::const_object_map_map_t db::to_const_map_objects(db::model const &model, db::object_data_vector_map_t const &datas) {
    db::const_object_map_map_t objects;
    for (auto const &entity_pair : datas) {
        auto const &entity_name = entity_pair.first;
        auto const &entity_datas = entity_pair.second;

        db::const_object_map_t entity_objects;
        entity_objects.reserve(entity_datas.size());

        for (auto const &data : entity_datas) {
            if (db::const_object obj{model.entity(entity_name), data}) {
                entity_objects.emplace(obj.object_id().get<db::integer>(), std::move(obj));
            }
        }

        objects.emplace(entity_name, std::move(entity_objects));
    }
    return objects;
}
