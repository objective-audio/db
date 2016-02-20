//
//  yas_db_utils.cpp
//

#include "yas_db_additional_protocol.h"
#include "yas_db_attribute.h"
#include "yas_db_database.h"
#include "yas_db_model.h"
#include "yas_db_row_set.h"
#include "yas_db_select_option.h"
#include "yas_db_sql_utils.h"
#include "yas_db_utils.h"
#include "yas_unless.h"

using namespace yas;

db::update_result db::create_table(db::database &db, std::string const &table_name,
                                   std::vector<std::string> const &fields) {
    return db.execute_update(create_table_sql(table_name, fields));
}

db::update_result db::alter_table(db::database &db, std::string const &table_name, std::string const &field) {
    return db.execute_update(alter_table_sql(table_name, field));
}

db::update_result db::drop_table(db::database &db, std::string const &table_name) {
    return db.execute_update(drop_table_sql(table_name));
}

db::update_result db::create_index(database &db, std::string const &index_name, std::string const &table_name,
                                   std::vector<std::string> const &fields) {
    return db.execute_update(create_index_sql(index_name, table_name, fields));
}

db::update_result db::drop_index(database &db, std::string const &index_name) {
    return db.execute_update(drop_index_sql(index_name));
}

db::update_result db::begin_transaction(db::database &db) {
    return db.execute_update("BEGIN EXCLUSIVE TRANSACTION");
}

db::update_result db::begin_deferred_transaction(db::database &db) {
    return db.execute_update("BEGIN DEFERRED TRANSACTION");
}

db::update_result db::commit(db::database &db) {
    return db.execute_update("COMMIT TRANSACTION");
}

db::update_result db::rollback(db::database &db) {
    return db.execute_update("ROLLBACK TRANSACTION");
}

#if SQLITE_VERSION_NUMBER >= 3007000

namespace yas {
namespace db {
    static std::string escape_save_point_name(std::string const &name) {
        return replaced(name, "'", "''");
    }
}
}

db::update_result db::start_save_point(db::database &db, std::string const &name) {
    if (name.size() == 0) {
        return update_result{error{error_type::invalid_argument}};
    }
    return db.execute_update("SAVEPOINT '" + escape_save_point_name(name) + "';");
}

db::update_result db::release_save_point(db::database &db, std::string const &name) {
    if (name.size() == 0) {
        return update_result{error{error_type::invalid_argument}};
    }
    return db.execute_update("RELEASE SAVEPOINT '" + escape_save_point_name(name) + "';");
}

db::update_result db::rollback_save_point(db::database &db, std::string const &name) {
    if (name.size() == 0) {
        return update_result{error{error_type::invalid_argument}};
    }
    return db.execute_update("ROLLBACK TRANSACTION TO SAVEPOINT '" + escape_save_point_name(name) + "';");
}

db::update_result db::in_save_point(db::database &db, std::function<void(bool &rollback)> const function) {
    static unsigned long save_point_idx = 0;
    std::string const name = "db_save_point_" + std::to_string(save_point_idx++);

    if (auto ul = unless(start_save_point(db, name))) {
        return std::move(ul.value);
    }

    bool should_rollback = false;

    function(should_rollback);

    if (should_rollback) {
        rollback_save_point(db, name);
    }

    return release_save_point(db, name);
}

#endif

bool db::table_exists(database const &db, std::string const &table_name) {
    if (auto row_set = get_table_schema(db, table_name)) {
        if (row_set.next()) {
            return true;
        }
    }
    return false;
}

bool db::index_exists(database const &db, std::string const &index_name) {
    if (auto row_set = get_index_schema(db, index_name)) {
        if (row_set.next()) {
            return true;
        }
    }
    return false;
}

db::row_set db::get_schema(database const &db) {
    if (auto query_result = db.execute_query(
            "select type, name, tbl_name, rootpage, sql from (select * from sqlite_master union all select * from "
            "sqlite_temp_master) where type != 'meta' and name not like 'sqlite_%' order by tbl_name, type desc, "
            "name")) {
        return query_result.value();
    }
    return nullptr;
}

db::row_set db::get_table_schema(database const &db, std::string const &table_name) {
    if (auto query_result = db.execute_query("PRAGMA table_info('" + table_name + "')")) {
        return query_result.value();
    }
    return nullptr;
}

db::row_set db::get_index_schema(database const &db, std::string const &index_name) {
    if (auto query_result =
            db.execute_query("SELECT * FROM sqlite_master WHERE type = 'index' AND name = '" + index_name + "';")) {
        return query_result.value();
    }
    return nullptr;
}

bool db::column_exists(database const &db, std::string column_name, std::string table_name) {
    std::string lower_table_name = to_lower(std::move(table_name));
    std::string lower_column_name = to_lower(std::move(column_name));

    if (auto row_set = get_table_schema(db, lower_table_name)) {
        while (row_set.next()) {
            auto value = row_set.column_value("name");
            if (to_lower(value.get<db::text>()) == lower_column_name) {
                return true;
            }
        }
    }

    return false;
}

db::select_result db::select(db::database const &db, select_option const &option) {
    auto const sql =
        select_sql(option.table, option.fields, option.where_exprs, option.field_orders, option.limit_range);

    db::value_map_vector value_map_vector;

    if (auto query_result = db.execute_query(sql, option.arguments)) {
        auto row_set = query_result.value();
        while (row_set.next()) {
            value_map_vector.emplace_back(row_set.value_map());
        }
    } else {
        return select_result{std::move(query_result.error())};
    }

    return select_result{value_map_vector};
}

db::select_result db::select_last(database const &db, select_option option, value const &save_id,
                                  bool const include_removed) {
    std::vector<std::string> components;

    if (save_id) {
        components.emplace_back(expr(save_id_field, "<=", to_string(save_id)));
    }

    if (option.where_exprs.size() > 0) {
        components.emplace_back(option.where_exprs);
    }

    std::string sub_where = components.size() > 0 ? " WHERE " + joined(components, " AND ") : "";

    std::string where_exprs =
        "rowid IN (SELECT MAX(rowid) FROM " + option.table + sub_where + " GROUP BY " + db::object_id_field + ")";
    if (!include_removed) {
        static std::string const exc_removed_expr = action_field + " != '" + remove_action + "'";
        where_exprs = joined({where_exprs, exc_removed_expr}, " AND ");
    }
    option.where_exprs = where_exprs;

    return select(db, option);
}

db::select_result db::select_undo(database const &db, std::string const &table_name, integer::type const revert_save_id,
                                  integer::type const current_save_id) {
    if (current_save_id <= revert_save_id) {
        throw "revert_save_id greater than or equal to current_save_id";
    }

    std::vector<std::string> components;
    components.emplace_back(object_id_field + " IN (SELECT DISTINCT " + object_id_field + " FROM " + table_name +
                            " WHERE " + joined({expr(save_id_field, "<=", std::to_string(current_save_id)),
                                                expr(save_id_field, ">", std::to_string(revert_save_id))},
                                               " AND ") +
                            ")");
    components.emplace_back(expr(save_id_field, "<=", std::to_string(revert_save_id)));

    select_option option{.table = table_name,
                         .where_exprs = "rowid IN (SELECT MAX(rowid) FROM " + table_name + " WHERE " +
                                        joined(components, " AND ") + " GROUP BY " + object_id_field + ")",
                         .field_orders = {{object_id_field, order::ascending}}};

    auto result = select(db, option);
    if (!result) {
        return select_result{std::move(result.error())};
    }

    select_option empty_option{.table = table_name,
                               .fields = {object_id_field},
                               .where_exprs = joined({expr(save_id_field, "<=", std::to_string(current_save_id)),
                                                      expr(save_id_field, ">", std::to_string(revert_save_id)),
                                                      equal_field_expr(action_field)},
                                                     " AND "),
                               .arguments = {{action_field, db::value{insert_action}}},
                               .field_orders = {{object_id_field, order::ascending}}};
    auto empty_result = select(db, empty_option);
    if (!empty_result) {
        return select_result{std::move(empty_result.error())};
    }

    return select_result{connect(std::move(result.value()), std::move(empty_result.value()))};
}

db::select_result db::select_redo(database const &db, std::string const &table_name, integer::type const revert_save_id,
                                  integer::type const current_save_id) {
    if (revert_save_id <= current_save_id) {
        throw "current_save_id greater than or equal to revert_save_id";
    }

    std::vector<std::string> components;
    components.emplace_back(expr(save_id_field, ">", std::to_string(current_save_id)));

    db::select_option option{.table = table_name,
                             .where_exprs = joined(components, " AND "),
                             .field_orders = {{object_id_field, db::order::ascending}}};

    return select_last(db, std::move(option), db::value{revert_save_id}, true);
}

db::select_result db::select_revert(database const &db, std::string const &table_name,
                                    integer::type const revert_save_id, integer::type const current_save_id) {
    if (revert_save_id < current_save_id) {
        return select_undo(db, table_name, revert_save_id, current_save_id);
    } else if (current_save_id < revert_save_id) {
        return select_redo(db, table_name, revert_save_id, current_save_id);
    }

    return select_result{value_map_vector{}};
}

db::select_single_result db::select_single(database const &db, select_option option) {
    option.limit_range = {.location = 0, .length = 1};

    if (auto result = select(db, option)) {
        if (result.value().size() > 0) {
            return select_single_result{std::move(result.value().at(0))};
        }
    }

    return select_single_result{nullptr};
}

db::select_single_result db::select_db_info(database const &db) {
    return select_single(db, db::select_option{.table = db::info_table});
}

db::value db::max(database const &db, std::string const &table_name, std::string const &field) {
    if (auto query_result = db.execute_query("SELECT MAX(" + field + ") FROM " + table_name + ";")) {
        auto &row_set = query_result.value();
        if (row_set.next()) {
            return row_set.column_value(0);
        }
    }
    return nullptr;
}

std::vector<db::const_object> db::get_const_relation_objects(const_object const &object,
                                                             const_object_map_map const &objects,
                                                             std::string const &rel_name) {
    auto const rel_ids = object.get_relation_ids(rel_name);
    std::string const &tgt_entity_name = object.model().relation(object.entity_name(), rel_name).target_entity_name;

    if (objects.count(tgt_entity_name) > 0) {
        auto const &entity_objects = objects.at(tgt_entity_name);
        return to_vector<db::const_object>(rel_ids,
                                           [&entity_objects, entity_name = object.entity_name()](db::value const &id) {
                                               if (entity_objects.count(id.get<integer>())) {
                                                   return entity_objects.at(id.get<integer>());
                                               }
                                               return db::const_object::null_object();
                                           });
    }

    return {};
}

db::const_object db::get_const_relation_object(const_object const &object, const_object_map_map const &objects,
                                               std::string const &rel_name, std::size_t const idx) {
    auto const rel_id = object.get_relation_ids(rel_name).at(idx).get<integer>();
    std::string const &tgt_entity_name = object.model().relation(object.entity_name(), rel_name).target_entity_name;

    if (objects.count(tgt_entity_name) > 0) {
        auto const &entity_objects = objects.at(tgt_entity_name);
        if (entity_objects.count(rel_id)) {
            return entity_objects.at(rel_id);
        }
    }

    return db::const_object::null_object();
}

db::object_map_map yas::to_object_map_map(db::object_vector_map objects_vector) {
    db::object_map_map objects_map;

    for (auto &entity_pair : objects_vector) {
        auto &entity_name = entity_pair.first;
        auto entity_objects = to_object_map(std::move(entity_pair.second));
        objects_map.emplace(std::make_pair(entity_name, std::move(entity_objects)));
    }

    objects_vector.clear();

    return objects_map;
}

db::object_map yas::to_object_map(db::object_vector vec) {
    db::object_map map;

    auto it = vec.begin();
    auto end = vec.end();
    while (it != end) {
        auto &obj = *it;
        auto obj_id = obj.object_id().get<db::integer>();
        map.emplace(std::make_pair(std::move(obj_id), std::move(obj)));
        ++it;
    }

    vec.clear();

    return map;
}
