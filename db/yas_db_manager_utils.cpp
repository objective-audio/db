//
//  yas_db_manager_utils.cpp
//

#include "yas_db_manager_utils.h"
#include <cpp_utils/yas_fast_each.h>
#include <cpp_utils/yas_result.h>
#include <cpp_utils/yas_stl_utils.h>
#include <cpp_utils/yas_unless.h>
#include "yas_db_attribute.h"
#include "yas_db_database.h"
#include "yas_db_entity.h"
#include "yas_db_fetch_option.h"
#include "yas_db_index.h"
#include "yas_db_info.h"
#include "yas_db_model.h"
#include "yas_db_object.h"
#include "yas_db_object_id.h"
#include "yas_db_relation.h"
#include "yas_db_sql_utils.h"
#include "yas_db_value.h"

using namespace yas;

namespace yas::db {
// 指定したsave_id以前で、object_idが同じなら最後のものをselectする条件
std::string last_where_exprs(std::string const &table, std::string const &where_exprs, db::value const &last_save_id,
                             bool const include_removed) {
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

    if (db::select_result_t select_result = db::select(db, option)) {
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
        std::string const &rel_name = rel_model_pair.first;
        std::string const &rel_table = rel_model_pair.second.table;

        if (db::value_vector_result_t result = db::select_relation_target_ids(db, rel_table, save_id, src_obj_id)) {
            relations.emplace(rel_name, std::move(result.value()));
        } else {
            return db::value_vector_map_result_t{std::move(result.error())};
        }
    }

    return db::value_vector_map_result_t{std::move(relations)};
}

static void get_relation_ids(db::integer_set_map_t &out_ids, db::object const &object) {
    for (auto const &rel_pair : object.entity().relations) {
        db::relation const &rel = rel_pair.second;
        std::string const &entity_name = rel.target;
        auto const &rel_ids = object.relation_ids(rel_pair.first);
        if (rel_ids.size() == 0) {
            continue;
        }
        if (out_ids.count(entity_name) == 0) {
            out_ids.emplace(entity_name, db::integer_set_t{});
        }
        auto &result_entity_ids = out_ids.at(entity_name);
        for (db::object_id const &rel_id : rel_ids) {
            if (rel_id.is_stable()) {
                result_entity_ids.emplace(rel_id.stable());
            }
        }
    }
}
}  // namespace yas::db

#pragma mark - select

db::select_result_t db::select_last(db::database const &db, db::select_option option, db::value const &save_id,
                                    bool const include_removed) {
    option.where_exprs = db::last_where_exprs(option.table, option.where_exprs, save_id, include_removed);
    return db::select(db, option);
}

db::select_result_t db::select_for_undo(db::database const &db, std::string const &table,
                                        db::integer::type const revert_save_id,
                                        db::integer::type const current_save_id) {
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

    db::select_result_t result = db::select(db, option);
    if (!result) {
        return result;
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

    db::select_result_t empty_result = db::select(db, empty_option);
    if (!empty_result) {
        return empty_result;
    }

    // キャッシュを上書きするためのデータを返す
    return db::select_result_t{connect(std::move(result.value()), std::move(empty_result.value()))};
}

db::select_result_t db::select_for_redo(db::database const &db, std::string const &table,
                                        db::integer::type const revert_save_id,
                                        db::integer::type const current_save_id) {
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

db::select_result_t db::select_for_revert(db::database const &db, std::string const &table,
                                          db::integer::type const revert_save_id,
                                          db::integer::type const current_save_id) {
    // リバート先のセーブIDによってアンドゥとリドゥに分岐する
    if (revert_save_id < current_save_id) {
        return db::select_for_undo(db, table, revert_save_id, current_save_id);
    } else if (current_save_id < revert_save_id) {
        return db::select_for_redo(db, table, revert_save_id, current_save_id);
    }

    return db::select_result_t{db::value_map_vector_t{}};
}

db::select_result_t db::select_for_save(db::database const &db, std::string const &entity_table,
                                        std::string const &rel_table, db::value_vector_t const &tgt_obj_ids) {
    // 最後のオブジェクトのpk_idを取得するsql
    std::string const last_exprs = db::last_where_exprs(entity_table, "", nullptr, false);
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

#pragma mark - info

db::manager_info_result_t db::fetch_info(db::database const &db) {
    if (db::select_single_result_t select_result = db::select_single(db, db::select_option{.table = db::info_table})) {
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

db::manager_result_t db::create_info(db::database &db, yas::version const &version) {
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

db::manager_info_result_t db::update_info(db::database &db, db::value const &cur_save_id,
                                          db::value const &last_save_id) {
    db::value_vector_t const params{cur_save_id, last_save_id};
    if (db::update_result_t update_result = db.execute_update(db::info::sql_for_update_save_ids(), params)) {
        if (db::manager_info_result_t select_result = db::fetch_info(db)) {
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
    if (db::update_result_t update_result = db.execute_update(db::info::sql_for_update_current_save_id(), params)) {
        if (db::manager_info_result_t select_result = db::fetch_info(db)) {
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
    if (db::update_result_t update_result =
            db.execute_update(db::info::sql_for_update_version(), {db::value{version.str()}})) {
        return db::manager_result_t{nullptr};
    } else {
        return db::make_error_result(db::manager_error_type::update_info_failed, std::move(update_result.error()));
    }
}

#pragma mark - convert

db::id_vector_t db::to_stable_ids(db::value_vector_t const &values) {
    return to_vector<db::object_id>(values, [](db::value const &value) { return db::make_stable_id(value); });
}

db::id_vector_map_t db::to_stable_ids(db::value_vector_map_t const &values) {
    db::id_vector_map_t result;
    result.reserve(values.size());
    for (auto const &pair : values) {
        result.emplace(pair.first, db::to_stable_ids(pair.second));
    }
    return result;
}

db::id_vector_t db::copy_ids(db::id_vector_t const &ids) {
    return to_vector<db::object_id>(ids, [](db::object_id const &obj_id) { return obj_id.copy(); });
}

db::value_vector_t db::to_values(db::id_vector_t const &ids) {
    return to_vector<db::value>(ids, [](db::object_id const &obj_id) { return obj_id.stable_value(); });
}

db::value_vector_map_t db::to_values(db::id_vector_map_t const &ids) {
    db::value_vector_map_t result;
    result.reserve(ids.size());
    for (auto const &pair : ids) {
        result.emplace(pair.first, db::to_values(pair.second));
    }
    return result;
}

// 複数のエンティティのobject_dataのvectorから、const_objectのvectorを生成する
db::const_object_vector_map_t db::to_const_vector_objects(db::model const &model,
                                                          db::object_data_vector_map_t const &datas) {
    db::const_object_vector_map_t objects;
    for (auto const &entity_pair : datas) {
        std::string const &entity_name = entity_pair.first;
        db::object_data_vector_t const &entity_datas = entity_pair.second;

        db::const_object_vector_t entity_objects;
        entity_objects.reserve(entity_datas.size());

        for (db::object_data const &data : entity_datas) {
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
        std::string const &entity_name = entity_pair.first;
        db::object_data_vector_t const &entity_datas = entity_pair.second;

        db::const_object_map_t entity_objects;
        entity_objects.reserve(entity_datas.size());

        for (db::object_data const &data : entity_datas) {
            if (db::const_object obj{model.entity(entity_name), data}) {
                entity_objects.emplace(obj.object_id().stable(), std::move(obj));
            }
        }

        objects.emplace(entity_name, std::move(entity_objects));
    }
    return objects;
}

db::fetch_option db::to_fetch_option(db::select_option sel_option) {
    db::fetch_option fetch_option{1};
    fetch_option.add_select_option(std::move(sel_option));
    return fetch_option;
}

db::fetch_option db::to_fetch_option(db::integer_set_map_t const &obj_ids) {
    db::fetch_option fetch_option{obj_ids.size()};

    for (auto const &pair : obj_ids) {
        fetch_option.add_select_option(
            {.table = pair.first, .where_exprs = db::in_expr(db::object_id_field, pair.second)});
    }

    return fetch_option;
}

db::fetch_ids_preparation_f db::to_ids_preparation(db::fetch_objects_preparation_f &&preparation) {
    return [preparation = std::move(preparation)]() {
        db::integer_set_map_t result_ids;
        db::object_vector_t objects = preparation();
        for (db::object const &object : objects) {
            db::get_relation_ids(result_ids, object);
        }
        return result_ids;
    };
}

db::fetch_ids_preparation_f db::to_ids_preparation(db::fetch_object_map_preparation_f &&preparation) {
    return [preparation = std::move(preparation)]() {
        db::integer_set_map_t result_ids;
        db::object_map_map_t objects = preparation();
        for (auto const &entity_pair : objects) {
            for (auto const &object_pair : entity_pair.second) {
                db::object const &object = object_pair.second;
                db::get_relation_ids(result_ids, object);
            }
        }
        return result_ids;
    };
}

db::fetch_ids_preparation_f db::to_ids_preparation(db::fetch_object_vector_preparation_f &&preparation) {
    return [preparation = std::move(preparation)]() {
        db::integer_set_map_t result_ids;
        db::object_vector_map_t objects = preparation();
        for (auto const &entity_pair : objects) {
            for (db::object const &object : entity_pair.second) {
                db::get_relation_ids(result_ids, object);
            }
        }
        return result_ids;
    };
}

#pragma mark - make

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
        db::id_vector_map_t rels;

        if (attrs.count(db::save_id_field) > 0) {
            db::value const &save_id = attrs.at(db::save_id_field);
            db::value const &src_obj_id = attrs.at(db::object_id_field);

            if (db::value_vector_map_result_t rel_data_result =
                    db::select_relation_data(db, rel_models, save_id, src_obj_id)) {
                rels = db::to_stable_ids(rel_data_result.value());
            } else {
                return db::object_data_vector_result_t{std::move(rel_data_result.error())};
            }
        }

        db::object_id obj_id = db::make_stable_id(attrs.at(db::object_id_field));

        entity_datas.emplace_back(db::object_data{
            .object_id = std::move(obj_id), .attributes = std::move(attrs), .relations = std::move(rels)});
    }

    return db::object_data_vector_result_t{std::move(entity_datas)};
}

#pragma mark - setup

db::manager_result_t db::migrate_db_if_needed(db::database &db, db::model const &model) {
    // infoからバージョンを取得。1つしかデータが無いこと前提
    if (db::manager_info_result_t select_result = db::fetch_info(db)) {
        // infoを現在のバージョンで上書き
        if (db::manager_result_t update_result = db::update_version(db, model.version())) {
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
        std::string const &entity_name = entity_pair.first;
        db::entity const &entity = entity_pair.second;

        if (db::table_exists(db, entity_name)) {
            // エンティティのテーブルがすでに存在している場合
            for (auto const &attr_pair : entity.all_attributes) {
                if (!db::column_exists(db, attr_pair.first, entity_name)) {
                    // テーブルにカラムが存在しなければalter tableを実行する
                    db::attribute const &attr = attr_pair.second;
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
            db::index const &index = index_pair.second;
            if (auto ul = unless(db.execute_update(index.sql_for_create()))) {
                return db::make_error_result(db::manager_error_type::create_index_failed, std::move(ul.value.error()));
            }
        }
    }

    return db::manager_result_t{nullptr};
}

db::manager_result_t db::create_info_and_tables(db::database &db, db::model const &model) {
    // infoテーブルをデータベース上に作成
    if (auto ul = unless(db::create_info(db, model.version()))) {
        return std::move(ul.value);
    }

    // 全てのエンティティと関連のテーブルをデータベース上に作成する
    auto const &entities = model.entities();
    for (auto &entity_pair : entities) {
        db::entity const &entity = entity_pair.second;
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
        db::index const &index = index_pair.second;
        if (auto ul = unless(db.execute_update(index.sql_for_create()))) {
            return db::make_error_result(db::manager_error_type::create_index_failed, std::move(ul.value.error()));
        }
    }

    return db::manager_result_t{nullptr};
}

db::manager_result_t db::clear_db(db::database &db, db::model const &model) {
    // トランザクション開始
    for (auto const &entity_pair : model.entities()) {
        db::entity const &entity = entity_pair.second;
        std::string const &entity_table_name = entity.name;

        // エンティティのテーブルのデータを全てデータベースから削除
        if (auto ul = unless(db.execute_update(db::delete_sql(entity_table_name)))) {
            return db::make_error_result(db::manager_error_type::delete_failed, std::move(ul.value.error()));
        }

        for (auto const &rel_pair : entity.relations) {
            std::string const rel_table_name = rel_pair.second.table;

            // 関連のテーブルのデータを全てデータベースから削除
            if (auto ul = unless(db.execute_update(db::delete_sql(rel_table_name)))) {
                return db::make_error_result(db::manager_error_type::delete_failed, std::move(ul.value.error()));
            }
        }
    }

    return db::manager_result_t{nullptr};
}

#pragma mark - editing

db::manager_fetch_result_t db::insert(db::database &db, db::model const &model, db::info const info,
                                      db::value_map_vector_map_t &&values) {
    if (info.current_save_id() < info.last_save_id()) {
        // カレントがラストより前ならカレントより後を削除する
        if (auto ul = unless(db::delete_next_to_last(db, model, info.current_save_id_value()))) {
            return db::manager_fetch_result_t{std::move(ul.value.error())};
        }
    }

    db::object_data_vector_map_t inserted_datas;
    db::integer::type start_obj_id = 1;
    db::value next_save_id = info.next_save_id_value();

    for (auto &values_pair : values) {
        std::string const &entity_name = values_pair.first;
        auto &entity_values = values_pair.second;

        // エンティティのデータ中のオブジェクトIDの最大値から次のIDを取得する
        // まだデータがなければ初期値の1のまま
        if (db::value const max_value = db::max(db, entity_name, db::object_id_field)) {
            start_obj_id = max_value.get<db::integer>() + 1;
        }

        std::size_t idx = 0;
        for (auto &obj_values : entity_values) {
            // オブジェクトの値を与えてデータベースに挿入する
            db::value obj_id_value{start_obj_id + idx};

            std::vector<std::string> fields{db::object_id_field, db::save_id_field};
            db::value_vector_t args{obj_id_value, next_save_id};

            fields.reserve(fields.size() + obj_values.size());
            args.reserve(args.size() + obj_values.size());

            for (auto &value : obj_values) {
                fields.push_back(value.first);
                args.emplace_back(std::move(value.second));
            }

            if (auto ul = unless(db.execute_update(db::insert_sql(entity_name, fields), std::move(args)))) {
                return db::manager_fetch_result_t{
                    db::manager_error{db::manager_error_type::insert_attributes_failed, std::move(ul.value.error())}};
            }

            // 挿入したオブジェクトのattributeをデータベースから取得する
            db::select_option option{.table = entity_name,
                                     .where_exprs = db::equal_field_expr(db::object_id_field),
                                     .arguments = {{std::make_pair(db::object_id_field, obj_id_value)}}};

            if (db::select_result_t select_result = db::select(db, std::move(option))) {
                // データをobject_dataにしてcompletionに返すinserted_datasに追加
                if (inserted_datas.count(entity_name) == 0) {
                    db::object_data_vector_t entity_datas{};
                    entity_datas.reserve(entity_values.size());
                    inserted_datas.emplace(entity_name, std::move(entity_datas));
                }

                auto &attributes = select_result.value().at(0);
                db::object_id obj_id = db::make_stable_id(attributes.at(db::object_id_field));
                inserted_datas.at(entity_name)
                    .emplace_back(db::object_data{.object_id = std::move(obj_id), .attributes = std::move(attributes)});
            } else {
                return db::manager_fetch_result_t{
                    db::manager_error{db::manager_error_type::select_failed, std::move(select_result.error())}};
            }

            ++idx;
        }
    }

    return db::manager_fetch_result_t{std::move(inserted_datas)};
}

db::manager_fetch_result_t db::fetch(db::database &db, db::model const &model, db::fetch_option const &fetch_option) {
    // カレントセーブIDをデータベースから取得
    db::value current_save_id = db::null_value();
    if (db::manager_info_result_t info_select_result = db::fetch_info(db)) {
        current_save_id = info_select_result.value().current_save_id_value();
    } else {
        return db::manager_fetch_result_t{std::move(info_select_result.error())};
    }

    db::object_data_vector_map_t fetched_datas;

    for (auto const &pair : fetch_option.select_options()) {
        std::string const entity_name = pair.first;
        db::select_option const &sel_option = pair.second;
        db::relation_map_t const &rel_models = model.relations(entity_name);

        // カレントセーブIDまでで条件にあった最後のデータをデータベースから取得する
        if (db::select_result_t select_result = db::select_last(db, sel_option, current_save_id)) {
            // アトリビュートのみのデータから関連のデータを加えてobject_dataを生成する
            auto &entity_attrs = select_result.value();
            if (auto obj_datas_result = db::make_entity_object_datas(db, entity_name, rel_models, entity_attrs)) {
                auto &entity_obj_datas = obj_datas_result.value();
                if (entity_obj_datas.size() > 0) {
                    fetched_datas.emplace(entity_name, std::move(entity_obj_datas));
                }
            } else {
                return db::manager_fetch_result_t{db::manager_error{db::manager_error_type::make_object_datas_failed,
                                                                    std::move(obj_datas_result.error())}};
            }
        } else {
            return db::manager_fetch_result_t{
                db::manager_error{db::manager_error_type::select_last_failed, std::move(select_result.error())}};
        }
    }

    return db::manager_fetch_result_t{std::move(fetched_datas)};
}

db::update_result_t db::purge_attributes(db::database &db, std::string const &table) {
    db::select_option const option{
        .table = table, .fields = {"MAX(" + db::pk_id_field + ")"}, .group_by = db::object_id_field};
    std::string const in_expr = db::in_expr("NOT " + db::pk_id_field, option);
    return db.execute_update(db::delete_sql(table, in_expr));
}

db::update_result_t db::purge_relations(database &db, std::string const &table, std::string const &src_table) {
    db::select_option const option{.table = src_table, .fields = {db::pk_id_field}};
    std::string const in_expr = db::in_expr("NOT " + db::src_pk_id_field, option);
    return db.execute_update(db::delete_sql(table, in_expr));
}

db::manager_result_t db::purge_db(db::database &db, db::model const &model) {
    // DB情報をデータベースから取得
    if (db::manager_info_result_t select_result = db::fetch_info(db)) {
        db::info const &db_info = select_result.value();
        if (db_info.current_save_id() < db_info.last_save_id()) {
            // ラストよりカレントのセーブIDが小さければ、カレントより大きいセーブIDのデータを削除
            // つまり、アンドゥした分を削除
            if (auto ul = unless(db::delete_next_to_last(db, model, db_info.current_save_id_value()))) {
                return db::manager_result_t{std::move(ul.value.error())};
            }
        }
    } else {
        return db::manager_result_t{std::move(select_result.error())};
    }

    std::vector<std::string> const save_id_fields{db::save_id_field};
    db::value_vector_t const one_value_args{db::value{db::integer::type{1}}};

    for (auto const &entity_pair : model.entities()) {
        std::string const &entity_name = entity_pair.first;
        db::entity const &entity = entity_pair.second;

        // エンティティのデータをパージする（同じオブジェクトIDのデータは最後のものだけ生かす）
        if (db::update_result_t purge_result = db::purge_attributes(db, entity_name)) {
            // 残ったデータのセーブIDを全て1にする
            std::string const update_entity_sql = db::update_sql(entity_name, save_id_fields);
            if (db::update_result_t update_result = db.execute_update(update_entity_sql, one_value_args)) {
                for (auto const &rel_pair : entity.relations) {
                    db::relation const &relation = rel_pair.second;
                    std::string const &rel_table_name = relation.table;

                    // 関連のデータをパージする（同じソースIDのデータは最後のものだけ生かす）
                    if (db::update_result_t purge_rel_result = db::purge_relations(db, rel_table_name, entity_name)) {
                        // 残ったデータのセーブIDを全て1にする
                        std::string const update_rel_sql = db::update_sql(rel_table_name, save_id_fields);
                        if (auto ul = unless(db.execute_update(update_rel_sql, one_value_args))) {
                            return db::make_error_result(db::manager_error_type::update_save_id_failed,
                                                         std::move(ul.value.error()));
                        }
                    } else {
                        return db::make_error_result(db::manager_error_type::purge_relation_failed,
                                                     std::move(purge_rel_result.error()));
                    }
                }
            } else {
                return db::make_error_result(db::manager_error_type::update_save_id_failed,
                                             std::move(update_result.error()));
            }
        } else {
            return db::make_error_result(db::manager_error_type::purge_failed, std::move(purge_result.error()));
        }
    }

    return db::manager_result_t{nullptr};
}

db::manager_fetch_result_t db::save(db::database &db, db::model const &model, db::info const &info,
                                    db::object_data_vector_map_t const &changed_datas) {
    // ラストのセーブIDよりカレントが前ならカレントより後のデータは削除する
    if (info.current_save_id() < info.last_save_id()) {
        if (auto ul = unless(db::delete_next_to_last(db, model, info.current_save_id_value()))) {
            return db::manager_fetch_result_t{std::move(ul.value.error())};
        }
    }

    db::object_data_vector_map_t saved_datas;

    db::value const next_save_id = info.next_save_id_value();
    auto const save_id_pair = std::make_pair(db::save_id_field, next_save_id);

    for (auto const &entity_pair : changed_datas) {
        std::string const &entity_name = entity_pair.first;
        auto const &changed_entity_datas = entity_pair.second;
        std::string const entity_insert_sql = model.entity(entity_name).sql_for_insert();

        db::object_data_vector_t entity_saved_datas;

        for (db::object_data changed_data : changed_entity_datas) {
            db::object_data saved_data{.object_id = db::null_id()};

            // 保存するデータのアトリビュートのidは削除する（rowidなのでいらない）
            erase_if_exists(changed_data.attributes, db::pk_id_field);
            // 保存するデータのセーブIDを今セーブするIDに置き換える
            replace(changed_data.attributes, db::save_id_field, next_save_id);

            if (changed_data.attributes.count(db::object_id_field) == 0) {
                // 保存するデータにまだオブジェクトIDがなければ（挿入されてtemporaryな状態）データベース上の最大値+1をセットする
                db::integer::type obj_id = 0;
                if (db::value max_value = db::max(db, entity_name, db::object_id_field)) {
                    obj_id = max_value.get<db::integer>();
                }
                db::integer::type const next_obj_id = obj_id + 1;
                replace(changed_data.attributes, db::object_id_field, db::value{next_obj_id});
                changed_data.object_id.set_stable(next_obj_id);
            }

            // データベースにアトリビュートのデータを挿入する
            if (db::update_result_t update_result = db.execute_update(entity_insert_sql, changed_data.attributes)) {
                saved_data.attributes = changed_data.attributes;
            } else {
                return db::manager_fetch_result_t{db::manager_error{db::manager_error_type::insert_attributes_failed,
                                                                    std::move(update_result.error())}};
            }

            // 挿入したデータのrowidを取得
            if (db::row_result_t row_result = db.last_insert_rowid()) {
                db::value pk_id{std::move(row_result.value())};
                saved_data.attributes.emplace(db::pk_id_field, std::move(pk_id));
            } else {
                return db::manager_fetch_result_t{
                    db::manager_error{db::manager_error_type::last_insert_rowid_failed, std::move(row_result.error())}};
            }

            saved_data.object_id = db::object_id{changed_data.attributes.at(db::object_id_field),
                                                 changed_data.object_id.temporary_value()};

            entity_saved_datas.emplace_back(std::move(saved_data));
        }

        saved_datas.emplace(entity_name, std::move(entity_saved_datas));
    }

    for (auto const &entity_pair : changed_datas) {
        std::string const &entity_name = entity_pair.first;
        auto const &changed_entity_datas = entity_pair.second;
        auto const &rel_models = model.relations(entity_name);
        auto &saved_entity_datas = saved_datas.at(entity_name);

        auto each = make_fast_each(changed_entity_datas.size());
        while (yas_each_next(each)) {
            std::size_t const &idx = yas_each_index(each);
            db::object_data const &changed_data = changed_entity_datas.at(idx);
            db::object_data &saved_data = saved_entity_datas.at(idx);

            db::value const &src_pk_id = saved_data.attributes.at(db::pk_id_field);
            db::value const &src_obj_id = saved_data.object_id.stable_value();

            for (auto const &rel_pair : changed_data.relations) {
                // データベースに関連のデータを挿入する
                db::relation const &rel_model = rel_models.at(rel_pair.first);
                db::value_vector_t rel_tgt_obj_ids = db::to_values(rel_pair.second);
                if (db::manager_result_t insert_result =
                        db::insert_relations(db, rel_model, src_pk_id, src_obj_id, rel_tgt_obj_ids, next_save_id)) {
                    saved_data.relations.emplace(rel_pair.first, rel_pair.second);
                } else {
                    return db::manager_fetch_result_t{std::move(insert_result.error())};
                }
            }
        }
    }

    return db::manager_fetch_result_t{std::move(saved_datas)};
}

db::manager_result_t db::remove_relations_at_save(db::database &db, db::model const &model, db::info const &info,
                                                  db::object_data_vector_map_t const &changed_datas) {
    // オブジェクトが削除された場合に逆関連があったらデータベース上で関連を外す
    db::value const next_save_id = info.next_save_id_value();

    for (auto const &entity_pair : changed_datas) {
        // エンティティごとの処理
        std::string const &entity_name = entity_pair.first;
        auto const &changed_entity_datas = entity_pair.second;
        auto const &inv_rel_names = model.entity(entity_name).inverse_relation_names;

        if (inv_rel_names.size() == 0) {
            // 逆関連が無ければスキップ
            continue;
        }

        // 削除されたobject_idを取得
        db::value_vector_t tgt_obj_ids;
        tgt_obj_ids.reserve(changed_entity_datas.size());

        for (db::object_data const &data : changed_entity_datas) {
            db::value const &action = data.attributes.at(db::action_field);
            if (action.get<db::text>() != db::remove_action) {
                // 削除されていなければスキップ
                continue;
            }

            tgt_obj_ids.push_back(data.attributes.at(db::object_id_field));
        }

        if (tgt_obj_ids.size() == 0) {
            // 削除されたオブジェクトがなければスキップ
            continue;
        }

        for (auto const &inv_entity_pair : inv_rel_names) {
            std::string const &inv_entity_name = inv_entity_pair.first;
            db::string_set_t const &rel_names = inv_entity_pair.second;

            db::value_map_map_t entity_attrs_map;

            // tgt_obj_idsが関連先に含まれているオブジェクトのアトリビュートを取得
            for (auto const &rel_name : rel_names) {
                db::relation const &rel = model.relation(inv_entity_name, rel_name);
                if (db::select_result_t select_result =
                        db::select_for_save(db, inv_entity_name, rel.table, tgt_obj_ids)) {
                    for (auto const &attr : select_result.value()) {
                        std::string obj_id_str = to_string(attr.at(db::object_id_field));
                        if (entity_attrs_map.count(obj_id_str) == 0) {
                            // object_idが被らないものだけ追加する。必ず最後のデータが来ているはず。
                            entity_attrs_map.emplace(std::move(obj_id_str), std::move(attr));
                        }
                    }
                } else {
                    return db::make_error_result(db::manager_error_type::select_relation_removed_failed,
                                                 std::move(select_result.error()));
                }
            }

            db::object_data_vector_t inv_removed_datas;

            if (entity_attrs_map.size() > 0) {
                // アトリビュートを元に関連を取得する
                // mapからvectorへ変換
                db::value_map_vector_t entity_attrs_vec =
                    to_vector<db::value_map_t>(entity_attrs_map, [](auto &pair) { return std::move(pair.second); });

                auto const &rel_models = model.relations(inv_entity_name);
                if (auto obj_datas_result =
                        db::make_entity_object_datas(db, inv_entity_name, rel_models, entity_attrs_vec)) {
                    // 同じidのオブジェクトは上書きかスキップする？
                    // すでにsaveしたものは被っていないはず
                    inv_removed_datas = std::move(obj_datas_result.value());
                } else {
                    return db::make_error_result(db::manager_error_type::make_object_datas_failed,
                                                 std::move(obj_datas_result.error()));
                }
            }

            if (inv_removed_datas.size() > 0) {
                std::string const &entity_insert_sql = model.entity(inv_entity_name).sql_for_insert();
                auto const &rel_models = model.relations(inv_entity_name);

                for (db::object_data &obj_data : inv_removed_datas) {
                    // 保存するデータのアトリビュートのidは削除する（rowidなのでいらない）
                    erase_if_exists(obj_data.attributes, db::pk_id_field);
                    // 保存するデータのセーブIDを今セーブするIDに置き換える
                    replace(obj_data.attributes, db::save_id_field, next_save_id);
                    replace(obj_data.attributes, db::object_id_field, obj_data.object_id.stable_value());
                    // データベースにアトリビュートのデータを挿入する
                    if (auto ul = unless(db.execute_update(entity_insert_sql, obj_data.attributes))) {
                        return db::make_error_result(db::manager_error_type::insert_attributes_failed,
                                                     std::move(ul.value.error()));
                        break;
                    }

                    // pk_idを取得してセットする
                    if (db::row_result_t row_result = db.last_insert_rowid()) {
                        db::value const src_pk_id = db::value{std::move(row_result.value())};
                        db::value const src_obj_id = obj_data.attributes.at(db::object_id_field);

                        for (auto const &rel_pair : obj_data.relations) {
                            // データベースに関連のデータを挿入する
                            db::relation const &rel_model = rel_models.at(rel_pair.first);
                            auto const rel_tgt_obj_ids =
                                filter(rel_pair.second, [&tgt_obj_ids](db::object_id const &obj_id) {
                                    return !contains(tgt_obj_ids, obj_id.stable_value());
                                });
                            if (rel_tgt_obj_ids.size() > 0) {
                                if (auto ul =
                                        unless(db::insert_relations(db, rel_model, src_pk_id, src_obj_id,
                                                                    db::to_values(rel_tgt_obj_ids), next_save_id))) {
                                    return std::move(ul.value);
                                }
                            }
                        }
                    } else {
                        return db::make_error_result(db::manager_error_type::last_insert_rowid_failed,
                                                     std::move(row_result.error()));
                    }
                }
            }
        }
    }

    return db::manager_result_t{nullptr};
}

// 指定したsave_idより大きいsave_idのデータを、全てのエンティティに対してデータベース上から削除する
db::manager_result_t db::delete_next_to_last(db::database &db, db::model const &model, db::value const &save_id) {
    auto const &entity_models = model.entities();
    std::string const delete_exprs = expr(db::save_id_field, ">", to_string(save_id));

    for (auto const &entity_pair : entity_models) {
        std::string const &entity_name = entity_pair.first;

        if (db::update_result_t delete_result = db.execute_update(db::delete_sql(entity_name, delete_exprs))) {
            for (auto const &rel_pair : entity_pair.second.relations) {
                std::string const table = rel_pair.second.table;

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
    std::string const &rel_insert_sql = rel_model.sql_for_insert();
    auto src_pk_id_pair = std::make_pair(db::src_pk_id_field, src_pk_id);
    auto src_obj_id_pair = std::make_pair(db::src_obj_id_field, src_obj_id);
    auto save_id_pair = std::make_pair(db::save_id_field, save_id);

    for (db::value const &rel_tgt_obj_id : rel_tgt_obj_ids) {
        auto tgt_obj_id_pair = std::make_pair(db::tgt_obj_id_field, rel_tgt_obj_id);

        db::value_map_t args{src_pk_id_pair, src_obj_id_pair, std::move(tgt_obj_id_pair), save_id_pair};
        if (auto ul = unless(db.execute_update(rel_insert_sql, std::move(args)))) {
            return db::make_error_result(db::manager_error_type::insert_relation_failed, std::move(ul.value.error()));
        }
    }
    return db::manager_result_t{nullptr};
}
