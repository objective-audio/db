//
//  yas_db_row_set.cpp
//

#include "yas_db_row_set.h"

#include <cpp_utils/yas_fast_each.h>
#include <cpp_utils/yas_result.h>
#include <cpp_utils/yas_stl_utils.h>

#include <vector>

#include "yas_db_database.h"
#include "yas_db_statement.h"

using namespace yas;
using namespace yas::db;

#pragma mark - code

db::next_result_code::next_result_code(int const &value) : result_code(value) {
}

db::next_result_code::operator bool() const {
    return this->raw_value() == SQLITE_ROW;
}

#pragma mark - row_set

row_set::row_set(db::statement_ptr const &statement, database_ptr const &database,
                 std::vector<db::value> const &context)
    : _statement(statement), _database(database), _context(context) {
    this->_statement->set_in_use(true);
}

row_set::~row_set() {
    this->close();
}

uintptr_t row_set::identifier() const {
    return reinterpret_cast<uintptr_t>(this);
}

db::statement_ptr const &row_set::statement() const {
    return this->_statement;
}

db::next_result_code row_set::next() {
    next_result_code result{sqlite3_step(this->statement()->stmt())};

    if (!result) {
        this->close();
    }

    return result;
}

bool row_set::has_row() {
    if (db::database_ptr const &database = this->_database) {
        if (sqlite3 *const sqlite_handle = database->sqlite_handle()) {
            return sqlite3_errcode(sqlite_handle) == SQLITE_ROW;
        }
    }
    return false;
}

int row_set::column_count() const {
    return sqlite3_column_count(this->statement()->stmt());
}

row_set::index_result_t row_set::column_index(std::string column_name) const {
    std::string lower_column_name = to_lower(std::move(column_name));

    auto const &map = this->_get_or_make_column_name_to_index_map();

    if (map.count(lower_column_name) > 0) {
        return row_set::index_result_t{map.at(lower_column_name)};
    }

    return row_set::index_result_t{nullptr};
}

std::string row_set::column_name(int const column_idx) const {
    return sqlite3_column_name(this->statement()->stmt(), column_idx);
}

bool row_set::column_is_null(int const column_idx) {
    return sqlite3_column_type(this->statement()->stmt(), column_idx) == SQLITE_NULL;
}

bool row_set::column_is_null(std::string column_name) {
    if (auto const index_result = column_index(std::move(column_name))) {
        return this->column_is_null(index_result.value());
    }
    return true;
}

db::value row_set::column_value(int const column_idx) const {
    if (column_idx >= 0) {
        sqlite3_stmt *const stmt = this->statement()->stmt();
        int type = sqlite3_column_type(stmt, column_idx);

        if (type != SQLITE_NULL) {
            if (type == SQLITE_INTEGER) {
                return db::value{sqlite3_column_int64(stmt, column_idx)};
            } else if (type == SQLITE_FLOAT) {
                return db::value{sqlite3_column_double(stmt, column_idx)};
            } else if (type == SQLITE_BLOB) {
                std::size_t const data_size = sqlite3_column_bytes(stmt, column_idx);
                const void *const data = sqlite3_column_blob(stmt, column_idx);
                return db::value{data, data_size};
            } else if (type == SQLITE_TEXT) {
                std::string text = (const char *)sqlite3_column_text(stmt, column_idx);
                return db::value{text};
            }
        }
    }

    return db::null_value();
}

db::value row_set::column_value(std::string column_name) const {
    if (auto index_result = column_index(std::move(column_name))) {
        return this->column_value(index_result.value());
    }
    return db::null_value();
}

db::value_map_t row_set::values() const {
    sqlite3_stmt *const stmt = this->statement()->stmt();
    int const column_count = sqlite3_data_count(stmt);

    db::value_map_t map;
    map.reserve(column_count);

    auto each = make_fast_each(column_count);
    while (yas_each_next(each)) {
        int const &idx = yas_each_index(each);
        map.insert(std::make_pair(sqlite3_column_name(stmt, idx), column_value(idx)));
    }

    return map;
}

void row_set::close() {
    this->_statement->reset();
    if (this->_database) {
        if (row_set_observable_ptr const observable_db = row_set_observable::cast(this->_database)) {
            observable_db->row_set_did_close(identifier());
        }
        this->_database = nullptr;
    }
}

void row_set::set_database(database_ptr const &database) {
    this->_database = database;
}

std::unordered_map<std::string, int> const &row_set::_get_or_make_column_name_to_index_map() const {
    if (this->_column_name_to_index_map.empty()) {
        sqlite3_stmt *const stmt = this->_statement->stmt();
        int column_count = sqlite3_column_count(stmt);
        auto each = make_fast_each(column_count);
        while (yas_each_next(each)) {
            int const &idx = yas_each_index(each);
            this->_column_name_to_index_map.insert(std::make_pair(to_lower(sqlite3_column_name(stmt, idx)), idx));
        }
    }

    return this->_column_name_to_index_map;
}

row_set_ptr row_set::make_shared(db::statement_ptr const &statement, database_ptr const &database,
                                 std::vector<db::value> const &context) {
    return row_set_ptr(new row_set{statement, database, context});
}
