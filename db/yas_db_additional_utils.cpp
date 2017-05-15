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

using namespace yas;

namespace yas {
namespace db {
    // 単独の関連の関連先のidの配列をDBから取得する
    db::value_vector_result_t select_relation_target_ids(db::database &db, std::string const &rel_table_name,
                                                         db::value const &save_id, db::value const &src_id) {
        std::string where_exprs =
            joined({db::equal_field_expr(db::save_id_field), db::equal_field_expr(db::src_obj_id_field)}, " and ");
        db::select_option option{.table = rel_table_name,
                                 .where_exprs = std::move(where_exprs),
                                 .arguments = {{db::save_id_field, save_id}, {db::src_obj_id_field, src_id}}};

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
                                                       db::value const &save_id, db::value const &src_id) {
        db::value_vector_map_t relations;

        for (auto const &rel_model_pair : rel_models) {
            auto const &rel_name = rel_model_pair.first;
            auto const &rel_table_name = rel_model_pair.second.table_name;

            if (auto select_result = db::select_relation_target_ids(db, rel_table_name, save_id, src_id)) {
                relations.emplace(std::make_pair(rel_name, std::move(select_result.value())));
            } else {
                return db::value_vector_map_result_t{std::move(select_result.error())};
            }
        }

        return db::value_vector_map_result_t{std::move(relations)};
    }
}
}

db::select_result_t db::select_last(db::database const &db, db::select_option option, db::value const &save_id,
                                    bool const include_removed) {
    std::vector<std::string> components;

    if (save_id) {
        components.emplace_back(db::expr(db::save_id_field, "<=", to_string(save_id)));
    }

    if (option.where_exprs.size() > 0) {
        components.emplace_back(option.where_exprs);
    }

    std::string sub_where = components.size() > 0 ? " WHERE " + joined(components, " AND ") : "";

    std::string where_exprs =
        "rowid IN (SELECT MAX(rowid) FROM " + option.table + sub_where + " GROUP BY " + db::object_id_field + ")";
    if (!include_removed) {
        static std::string const exc_removed_expr = db::action_field + " != '" + db::remove_action + "'";
        where_exprs = joined({where_exprs, exc_removed_expr}, " AND ");
    }
    option.where_exprs = where_exprs;

    return db::select(db, option);
}

db::select_result_t db::select_undo(db::database const &db, std::string const &table_name,
                                    db::integer::type const revert_save_id, db::integer::type const current_save_id) {
    if (current_save_id <= revert_save_id) {
        throw "revert_save_id greater than or equal to current_save_id";
    }

    std::vector<std::string> components;
    components.emplace_back(db::object_id_field + " IN (SELECT DISTINCT " + db::object_id_field + " FROM " +
                            table_name + " WHERE " +
                            joined({db::expr(db::save_id_field, "<=", std::to_string(current_save_id)),
                                    db::expr(db::save_id_field, ">", std::to_string(revert_save_id))},
                                   " AND ") +
                            ")");
    components.emplace_back(db::expr(db::save_id_field, "<=", std::to_string(revert_save_id)));

    db::select_option option{.table = table_name,
                             .where_exprs = "rowid IN (SELECT MAX(rowid) FROM " + table_name + " WHERE " +
                                            joined(components, " AND ") + " GROUP BY " + db::object_id_field + ")",
                             .field_orders = {{db::object_id_field, db::order::ascending}}};

    auto result = db::select(db, option);
    if (!result) {
        return db::select_result_t{std::move(result.error())};
    }

    db::select_option empty_option{
        .table = table_name,
        .fields = {db::object_id_field},
        .where_exprs = joined(
            {db::expr(db::save_id_field, "<=", std::to_string(current_save_id)),
             db::expr(db::save_id_field, ">", std::to_string(revert_save_id)), db::equal_field_expr(db::action_field)},
            " AND "),
        .arguments = {{db::action_field, db::value{db::insert_action}}},
        .field_orders = {{db::object_id_field, db::order::ascending}}};
    auto empty_result = db::select(db, empty_option);
    if (!empty_result) {
        return db::select_result_t{std::move(empty_result.error())};
    }

    return db::select_result_t{connect(std::move(result.value()), std::move(empty_result.value()))};
}

db::select_result_t db::select_redo(db::database const &db, std::string const &table_name,
                                    db::integer::type const revert_save_id, db::integer::type const current_save_id) {
    if (revert_save_id <= current_save_id) {
        throw "current_save_id greater than or equal to revert_save_id";
    }

    std::vector<std::string> components;
    components.emplace_back(db::expr(db::save_id_field, ">", std::to_string(current_save_id)));

    db::select_option option{.table = table_name,
                             .where_exprs = joined(components, " AND "),
                             .field_orders = {{db::object_id_field, db::order::ascending}}};

    return db::select_last(db, std::move(option), db::value{revert_save_id}, true);
}

db::select_result_t db::select_revert(db::database const &db, std::string const &table_name,
                                      db::integer::type const revert_save_id, db::integer::type const current_save_id) {
    if (revert_save_id < current_save_id) {
        return db::select_undo(db, table_name, revert_save_id, current_save_id);
    } else if (current_save_id < revert_save_id) {
        return db::select_redo(db, table_name, revert_save_id, current_save_id);
    }

    return db::select_result_t{db::value_map_vector_t{}};
}

db::select_single_result_t db::select_db_info(db::database const &db) {
    return db::select_single(db, db::select_option{.table = db::info_table});
}

db::update_result_t db::purge(db::database &db, std::string const &table_name) {
    std::string where_exprs =
        "NOT rowid IN (SELECT MAX(rowid) FROM " + table_name + " GROUP BY " + db::object_id_field + ")";
    return db.execute_update(db::delete_sql(table_name, where_exprs));
}

db::update_result_t db::purge_relation(database &db, std::string const &table_name, std::string const &src_table_name) {
    std::string where_exprs = "NOT " + db::src_id_field + " IN (SELECT rowid FROM " + src_table_name + ")";
    return db.execute_update(db::delete_sql(table_name, where_exprs));
}

db::manager::result_t db::make_error_result(db::manager::error_type const &error_type, db::error db_error) {
    return db::manager::result_t{db::manager::error{error_type, std::move(db_error)}};
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
            auto const &src_id = attrs.at(db::object_id_field);

            if (auto rel_data_result = db::select_relation_data(db, rel_models, save_id, src_id)) {
                rels = std::move(rel_data_result.value());
            } else {
                return db::object_data_vector_result_t{std::move(rel_data_result.error())};
            }
        }

        entity_datas.emplace_back(db::object_data{std::move(attrs), std::move(rels)});
    }

    return db::object_data_vector_result_t{std::move(entity_datas)};
}

// データベース情報からcurrent_save_idを取得する
db::manager::value_result_t db::select_current_save_id(db::database &db) {
    db::manager::result_t state{nullptr};

    auto current_save_id = db::value::null_value();
    if (auto db_info_result = db::select_db_info(db)) {
        auto &db_info = db_info_result.value();
        if (db_info.count(db::current_save_id_field) > 0) {
            current_save_id = db_info.at(db::current_save_id_field);
        } else {
            state = db::make_error_result(manager::error_type::save_id_not_found);
        }
    } else {
        state = db::make_error_result(manager::error_type::select_info_failed, std::move(db_info_result.error()));
    }

    if (state) {
        return db::manager::value_result_t{std::move(current_save_id)};
    } else {
        return db::manager::value_result_t{state.error()};
    }
}

// 指定したsave_idより大きいsave_idのデータを、全てのエンティティに対してデータベース上から削除する
db::manager::result_t db::delete_next_to_last(db::database &db, db::model const &model, db::value const &save_id) {
    auto const &entity_models = model.entities();
    auto const delete_exprs = expr(db::save_id_field, ">", to_string(save_id));

    for (auto const &entity_pair : entity_models) {
        auto const &entity_name = entity_pair.first;

        if (auto delete_result = db.execute_update(db::delete_sql(entity_name, delete_exprs))) {
            for (auto const &rel_pair : entity_pair.second.relations) {
                auto const table_name = rel_pair.second.table_name;

                if (auto ul = unless(db.execute_update(db::delete_sql(table_name, delete_exprs)))) {
                    return db::make_error_result(db::manager::error_type::delete_failed, std::move(ul.value.error()));
                }
            }
        } else {
            return db::make_error_result(db::manager::error_type::delete_failed, std::move(delete_result.error()));
        }
    }

    return db::manager::result_t{nullptr};
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

        objects.emplace(std::make_pair(entity_name, std::move(entity_objects)));
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
                entity_objects.emplace(std::make_pair(obj.object_id().get<db::integer>(), std::move(obj)));
            }
        }

        objects.emplace(std::make_pair(entity_name, std::move(entity_objects)));
    }
    return objects;
}
