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
#include "yas_result.h"
#include "yas_stl_utils.h"
#include "yas_unless.h"

using namespace yas;

db::update_result_t db::create_table(db::database &db, std::string const &table_name,
                                     std::vector<std::string> const &fields) {
    return db.execute_update(db::create_table_sql(table_name, fields));
}

db::update_result_t db::alter_table(db::database &db, std::string const &table_name, std::string const &field) {
    return db.execute_update(db::alter_table_sql(table_name, field));
}

db::update_result_t db::drop_table(db::database &db, std::string const &table_name) {
    return db.execute_update(db::drop_table_sql(table_name));
}

db::update_result_t db::create_index(db::database &db, std::string const &index_name, std::string const &table_name,
                                     std::vector<std::string> const &fields) {
    return db.execute_update(db::create_index_sql(index_name, table_name, fields));
}

db::update_result_t db::drop_index(db::database &db, std::string const &index_name) {
    return db.execute_update(db::drop_index_sql(index_name));
}

db::update_result_t db::begin_transaction(db::database &db) {
    return db.execute_update("BEGIN EXCLUSIVE TRANSACTION");
}

db::update_result_t db::begin_deferred_transaction(db::database &db) {
    return db.execute_update("BEGIN DEFERRED TRANSACTION");
}

db::update_result_t db::commit(db::database &db) {
    return db.execute_update("COMMIT TRANSACTION");
}

db::update_result_t db::rollback(db::database &db) {
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

db::update_result_t db::start_save_point(db::database &db, std::string const &name) {
    if (name.size() == 0) {
        return db::update_result_t{db::error{db::error_type::invalid_argument}};
    }
    return db.execute_update("SAVEPOINT '" + db::escape_save_point_name(name) + "';");
}

db::update_result_t db::release_save_point(db::database &db, std::string const &name) {
    if (name.size() == 0) {
        return db::update_result_t{db::error{db::error_type::invalid_argument}};
    }
    return db.execute_update("RELEASE SAVEPOINT '" + escape_save_point_name(name) + "';");
}

db::update_result_t db::rollback_save_point(db::database &db, std::string const &name) {
    if (name.size() == 0) {
        return db::update_result_t{db::error{db::error_type::invalid_argument}};
    }
    return db.execute_update("ROLLBACK TRANSACTION TO SAVEPOINT '" + escape_save_point_name(name) + "';");
}

db::update_result_t db::in_save_point(db::database &db, std::function<void(bool &rollback)> const function) {
    static unsigned long save_point_idx = 0;
    std::string const name = "db_save_point_" + std::to_string(save_point_idx++);

    if (auto ul = unless(db::start_save_point(db, name))) {
        return std::move(ul.value);
    }

    bool should_rollback = false;

    function(should_rollback);

    if (should_rollback) {
        db::rollback_save_point(db, name);
    }

    return db::release_save_point(db, name);
}

#endif

bool db::table_exists(db::database const &db, std::string const &table_name) {
    if (auto row_set = db::get_table_schema(db, table_name)) {
        if (row_set.next()) {
            return true;
        }
    }
    return false;
}

bool db::index_exists(db::database const &db, std::string const &index_name) {
    if (auto row_set = db::get_index_schema(db, index_name)) {
        if (row_set.next()) {
            return true;
        }
    }
    return false;
}

db::row_set db::get_schema(db::database const &db) {
    if (auto query_result = db.execute_query(
            "select type, name, tbl_name, rootpage, sql from (select * from sqlite_master union all select * from "
            "sqlite_temp_master) where type != 'meta' and name not like 'sqlite_%' order by tbl_name, type desc, "
            "name")) {
        return query_result.value();
    }
    return nullptr;
}

db::row_set db::get_table_schema(db::database const &db, std::string const &table_name) {
    if (auto query_result = db.execute_query("PRAGMA table_info('" + table_name + "')")) {
        return query_result.value();
    }
    return nullptr;
}

db::row_set db::get_index_schema(db::database const &db, std::string const &index_name) {
    if (auto query_result =
            db.execute_query("SELECT * FROM sqlite_master WHERE type = 'index' AND name = '" + index_name + "';")) {
        return query_result.value();
    }
    return nullptr;
}

bool db::column_exists(db::database const &db, std::string column_name, std::string table_name) {
    std::string lower_table_name = to_lower(std::move(table_name));
    std::string lower_column_name = to_lower(std::move(column_name));

    if (auto row_set = db::get_table_schema(db, lower_table_name)) {
        while (row_set.next()) {
            auto value = row_set.column_value("name");
            if (to_lower(value.get<db::text>()) == lower_column_name) {
                return true;
            }
        }
    }

    return false;
}

db::select_result_t db::select(db::database const &db, db::select_option const &option) {
    auto const sql =
        db::select_sql(option.table, option.fields, option.where_exprs, option.field_orders, option.limit_range);

    db::value_map_vector_t value_map_vector_t;

    if (auto query_result = db.execute_query(sql, option.arguments)) {
        auto row_set = query_result.value();
        while (row_set.next()) {
            value_map_vector_t.emplace_back(row_set.value_map_t());
        }
    } else {
        return db::select_result_t{std::move(query_result.error())};
    }

    return db::select_result_t{value_map_vector_t};
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

db::select_single_result_t db::select_single(db::database const &db, db::select_option option) {
    option.limit_range = {.location = 0, .length = 1};

    if (auto result = db::select(db, option)) {
        if (result.value().size() > 0) {
            return db::select_single_result_t{std::move(result.value().at(0))};
        }
    }

    return db::select_single_result_t{nullptr};
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

db::value db::max(database const &db, std::string const &table_name, std::string const &field) {
    if (auto query_result = db.execute_query("SELECT MAX(" + field + ") FROM " + table_name + ";")) {
        auto &row_set = query_result.value();
        if (row_set.next()) {
            return row_set.column_value(0);
        }
    }
    return nullptr;
}
