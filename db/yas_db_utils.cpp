//
//  yas_db_utils.cpp
//

#include "yas_db_utils.h"
#include <cpp_utils/yas_result.h>
#include <cpp_utils/yas_stl_utils.h>
#include <cpp_utils/yas_unless.h>
#include "yas_db_additional_protocol.h"
#include "yas_db_attribute.h"
#include "yas_db_database.h"
#include "yas_db_error.h"
#include "yas_db_model.h"
#include "yas_db_row_set.h"
#include "yas_db_select_option.h"
#include "yas_db_sql_utils.h"

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

namespace yas::db {
static std::string escape_save_point_name(std::string const &name) {
    return replaced(name, "'", "''");
}
}  // namespace yas::db

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
    if (db::row_set row_set = db::get_table_schema(db, table_name)) {
        if (row_set.next()) {
            return true;
        }
    }
    return false;
}

bool db::index_exists(db::database const &db, std::string const &index_name) {
    if (db::row_set row_set = db::get_index_schema(db, index_name)) {
        if (row_set.next()) {
            return true;
        }
    }
    return false;
}

db::row_set db::get_schema(db::database const &db) {
    if (db::query_result_t result = db.execute_query(
            "select type, name, tbl_name, rootpage, sql from (select * from sqlite_master union all select * from "
            "sqlite_temp_master) where type != 'meta' and name not like 'sqlite_%' order by tbl_name, type desc, "
            "name")) {
        return result.value();
    }
    return nullptr;
}

db::row_set db::get_table_schema(db::database const &db, std::string const &table_name) {
    if (db::query_result_t result = db.execute_query("PRAGMA table_info('" + table_name + "')")) {
        return result.value();
    }
    return nullptr;
}

db::row_set db::get_index_schema(db::database const &db, std::string const &index_name) {
    if (db::query_result_t result =
            db.execute_query("SELECT * FROM sqlite_master WHERE type = 'index' AND name = '" + index_name + "';")) {
        return result.value();
    }
    return nullptr;
}

bool db::column_exists(db::database const &db, std::string column_name, std::string table_name) {
    std::string lower_table_name = to_lower(std::move(table_name));
    std::string lower_column_name = to_lower(std::move(column_name));

    if (db::row_set row_set = db::get_table_schema(db, lower_table_name)) {
        while (row_set.next()) {
            db::value value = row_set.column_value("name");
            if (to_lower(value.get<db::text>()) == lower_column_name) {
                return true;
            }
        }
    }

    return false;
}

db::select_result_t db::select(db::database const &db, db::select_option const &option) {
    std::string const sql = db::select_sql(option) + ";";

    db::value_map_vector_t value_map_vector;

    if (db::query_result_t result = db.execute_query(sql, option.arguments)) {
        auto row_set = result.value();
        while (row_set.next()) {
            value_map_vector.emplace_back(row_set.values());
        }
    } else {
        return db::select_result_t{std::move(result.error())};
    }

    return db::select_result_t{value_map_vector};
}

db::select_single_result_t db::select_single(db::database const &db, db::select_option option) {
    option.limit_range = {.location = 0, .length = 1};

    if (db::select_result_t result = db::select(db, option)) {
        if (result.value().size() > 0) {
            return db::select_single_result_t{std::move(result.value().at(0))};
        }
    }

    return db::select_single_result_t{nullptr};
}

db::value db::max(database const &db, std::string const &table_name, std::string const &field) {
    if (db::query_result_t result = db.execute_query("SELECT MAX(" + field + ") FROM " + table_name + ";")) {
        auto &row_set = result.value();
        if (row_set.next()) {
            return row_set.column_value(0);
        }
    }
    return nullptr;
}
