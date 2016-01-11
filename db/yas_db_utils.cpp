//
//  yas_db_utils.cpp
//

#include "yas_db_attribute.h"
#include "yas_db_database.h"
#include "yas_db_order.h"
#include "yas_db_range.h"
#include "yas_db_row_set.h"
#include "yas_db_sql_utils.h"
#include "yas_db_utils.h"

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

db::update_result db::begin_transaction(db::database &db) {
    return db.execute_update("begin exclusive transaction");
}

db::update_result db::begin_deferred_transaction(db::database &db) {
    return db.execute_update("begin deferred transaction");
}

db::update_result db::commit(db::database &db) {
    return db.execute_update("commit transaction");
}

db::update_result db::rollback(db::database &db) {
    return db.execute_update("rollback transaction");
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
        return update_result{error_type::invalid_argument};
    }
    return db.execute_update("savepoint '" + escape_save_point_name(name) + "';");
}

db::update_result db::release_save_point(db::database &db, std::string const &name) {
    if (name.size() == 0) {
        return update_result{error_type::invalid_argument};
    }
    return db.execute_update("release savepoint '" + escape_save_point_name(name) + "';");
}

db::update_result db::rollback_save_point(db::database &db, std::string const &name) {
    if (name.size() == 0) {
        return update_result{error_type::invalid_argument};
    }
    return db.execute_update("rollback transaction to savepoint '" + escape_save_point_name(name) + "';");
}

db::update_result db::in_save_point(db::database &db, std::function<void(bool &rollback)> const function) {
    static unsigned long save_point_idx = 0;
    std::string const name = "db_save_point_" + std::to_string(save_point_idx++);

    auto start_result = start_save_point(db, name);
    if (!start_result) {
        return start_result;
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
    if (auto query_result = db.execute_query("pragma table_info('" + table_name + "')")) {
        return query_result.value();
    }
    return nullptr;
}

bool db::column_exists(database const &db, std::string const &column_name, std::string const &table_name) {
    std::string lower_table_name = to_lower(table_name);
    std::string lower_column_name = to_lower(column_name);

    if (auto row_set = get_table_schema(db, table_name)) {
        while (row_set.next()) {
            auto value = row_set.column_value("name");
            if (to_lower(value.get<db::text>()) == column_name) {
                return true;
            }
        }
    }

    return false;
}

db::select_result db::select_last(database const &db, std::string const &table_name) {
    std::string where_expr =
        "rowid in (select max(rowid) from " + table_name + " group by " + db::object_id_field + ")";

    std::string sql = select_sql(table_name, {"*"}, where_expr);

    if (auto query_result = db.execute_query(sql)) {
        auto row_set = query_result.value();
        std::vector<db::column_map> column_map;
        while (row_set.next()) {
            column_map.emplace_back(row_set.column_map());
        }
        if (column_map.size() > 0) {
            return select_result{column_map};
        } else {
            return select_result{select_error::not_found};
        }
    } else {
        return select_result{select_error::query_failed};
    }
}

std::vector<db::column_map> db::select(db::database const &db, std::string const &table_name,
                                       std::vector<std::string> const &fields, std::string const &where_exprs,
                                       std::vector<db::column_map> const &parameter_maps,
                                       std::vector<db::field_order> const &orders, db::range const &limit_range) {
    auto const sql = select_sql(table_name, fields, where_exprs, orders, limit_range);

    std::vector<db::column_map> result_map;

    if (parameter_maps.size() > 0) {
        for (auto &parameter_map : parameter_maps) {
            if (auto query_result = db.execute_query(sql, parameter_map)) {
                auto row_set = query_result.value();
                while (row_set.next()) {
                    result_map.emplace_back(row_set.column_map());
                }
            }
        }
    } else {
        if (auto query_result = db.execute_query(sql)) {
            auto row_set = query_result.value();
            while (row_set.next()) {
                result_map.emplace_back(row_set.column_map());
            }
        }
    }

    return result_map;
}

db::value db::max(database const &db, std::string const &table_name, std::string const &field) {
    if (auto query_result = db.execute_query("select max(" + field + ") from " + table_name + ";")) {
        auto &row_set = query_result.value();
        if (row_set.next()) {
            return row_set.column_value(0);
        }
    }
    return nullptr;
}
