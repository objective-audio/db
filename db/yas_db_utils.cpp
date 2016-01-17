//
//  yas_db_utils.cpp
//

#include "yas_db_attribute.h"
#include "yas_db_database.h"
#include "yas_db_manager.h"
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
        return update_result{error{error_type::invalid_argument}};
    }
    return db.execute_update("savepoint '" + escape_save_point_name(name) + "';");
}

db::update_result db::release_save_point(db::database &db, std::string const &name) {
    if (name.size() == 0) {
        return update_result{error{error_type::invalid_argument}};
    }
    return db.execute_update("release savepoint '" + escape_save_point_name(name) + "';");
}

db::update_result db::rollback_save_point(db::database &db, std::string const &name) {
    if (name.size() == 0) {
        return update_result{error{error_type::invalid_argument}};
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

db::select_result db::select(db::database const &db, std::string const &table_name,
                             std::vector<std::string> const &fields, std::string const &where_exprs,
                             db::value_map const args, std::vector<db::field_order> const &orders,
                             db::range const &limit_range) {
    auto const sql = select_sql(table_name, fields, where_exprs, orders, limit_range);

    db::value_map_vector value_map_vector;

    auto query_result = db.execute_query(sql, args);
    if (query_result) {
        auto row_set = query_result.value();
        while (row_set.next()) {
            value_map_vector.emplace_back(row_set.value_map());
        }
    } else {
        return select_result{std::move(query_result.error())};
    }

    return select_result{value_map_vector};
}

db::select_result db::select_last(database const &db, std::string const &table_name, db::value const &save_id,
                                  std::string const &where_exprs, db::value_map const args,
                                  std::vector<db::field_order> const &orders, db::range const &limit_range) {
    std::vector<std::string> sub_where_components;
    if (save_id) {
        sub_where_components.emplace_back(expr(save_id_field, to_string(save_id), "<="));
    }
    if (where_exprs.size() > 0) {
        sub_where_components.push_back(where_exprs);
    }
    std::string sub_where = sub_where_components.size() > 0 ? " where " + joined(sub_where_components, " and ") : "";
    std::string where =
        "rowid in (select max(rowid) from " + table_name + sub_where + " group by " + db::object_id_field + ")";
    return select(db, table_name, {"*"}, where, args, orders, limit_range);
}

db::select_single_result db::select_db_info(database const &db) {
    if (auto const &select_result = select(db, db::info_table, {"*"})) {
        if (select_result.value().size() > 0) {
            return select_single_result{std::move(select_result.value().at(0))};
        }
    }
    return select_single_result{nullptr};
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
