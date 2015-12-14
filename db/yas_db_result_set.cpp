//
//  yas_db_result_set.cpp
//

#include <vector>
#include "yas_db_column_value.h"
#include "yas_db_database.h"
#include "yas_db_result_set.h"
#include "yas_db_statement.h"
#include "yas_stl_utils.h"

using namespace yas;

#pragma mark - code

db::next_result_code::next_result_code(int const &value) : result_code(value) {
}

db::next_result_code::operator bool() const {
    return raw_value() == SQLITE_ROW;
}

#pragma mark - impl

class db::result_set::impl : public base::impl {
   public:
    impl(const db::statement &statement, database const &database) : _statement(statement), _database(database) {
        _statement.in_use().set_value(true);
    }

    ~impl() {
        close();
    }

    void close() {
        _statement.reset();
        if (_database) {
            if (auto observable_db = dynamic_cast<result_set_observable *>(&_database)) {
                observable_db->_result_set_did_close(identifier());
            }
            _database = nullptr;
        }
    }

    void set_database(database const &database) {
        _database = database;
    }

    database const &database() const {
        return _database;
    }

    const db::statement &statement() const {
        return _statement;
    }

    const std::unordered_map<std::string, int> &column_name_to_index_map() const {
        if (_column_name_to_index_map.empty()) {
            auto *const stmt = _statement.stmt().value();
            int column_count = sqlite3_column_count(stmt);
            for (int idx = 0; idx < column_count; ++idx) {
                _column_name_to_index_map.insert(std::make_pair(to_lower(sqlite3_column_name(stmt, idx)), idx));
            }
        }

        return _column_name_to_index_map;
    }

    std::string query;

   private:
    db::database _database;
    db::statement _statement;

    mutable std::unordered_map<std::string, int> _column_name_to_index_map;
};

db::result_set::result_set(const db::statement &statement, database const &database)
    : super_class(std::make_unique<impl>(statement, database)) {
}

db::result_set::result_set(std::nullptr_t) : super_class(nullptr) {
}

db::result_set::~result_set() = default;

bool db::result_set::operator==(std::nullptr_t) const {
    return super_class::operator==(nullptr);
}

bool db::result_set::operator!=(std::nullptr_t) const {
    return super_class::operator!=(nullptr);
}

void db::result_set::set_query(std::string const &query) {
    impl_ptr<impl>()->query = query;
}

std::string db::result_set::query() const {
    return impl_ptr<impl>()->query;
}

const db::statement &db::result_set::statement() const {
    return impl_ptr<impl>()->statement();
}

db::next_result_code db::result_set::next() {
    auto result = next_result_code(sqlite3_step(impl_ptr<impl>()->statement().stmt().value()));

    if (!result) {
        impl_ptr<impl>()->close();
    }

    return result;
}

bool db::result_set::has_another_row() {
    if (auto const database = impl_ptr<impl>()->database()) {
        if (auto const sqlite_handle = database.sqlite_handle()) {
            return sqlite3_errcode(sqlite_handle) == SQLITE_ROW;
        }
    }
    return false;
}

int db::result_set::column_count() const {
    return sqlite3_column_count(impl_ptr<impl>()->statement().stmt().value());
}

db::result_set::index_result db::result_set::column_index(std::string const &column_name) const {
    std::string lower_column_name = to_lower(column_name);

    auto const &map = impl_ptr<impl>()->column_name_to_index_map();

    if (map.count(lower_column_name) > 0) {
        return index_result{map.at(lower_column_name)};
    }

    return index_result{nullptr};
}

std::string db::result_set::column_name(int const column_idx) const {
    return sqlite3_column_name(impl_ptr<impl>()->statement().stmt().value(), column_idx);
}

bool db::result_set::column_is_null(int const column_idx) {
    return sqlite3_column_type(impl_ptr<impl>()->statement().stmt().value(), column_idx) == SQLITE_NULL;
}

bool db::result_set::column_is_null(std::string const column_name) {
    if (auto const index_result = column_index(column_name)) {
        return column_is_null(index_result.value());
    }
    return true;
}

db::column_value db::result_set::column_value(int const column_idx) const {
    if (column_idx >= 0) {
        auto *const stmt = impl_ptr<impl>()->statement().stmt().value();
        int type = sqlite3_column_type(stmt, column_idx);

        if (type != SQLITE_NULL) {
            if (type == SQLITE_INTEGER) {
                return db::column_value{sqlite3_column_int64(stmt, column_idx)};
            } else if (type == SQLITE_FLOAT) {
                return db::column_value{sqlite3_column_double(stmt, column_idx)};
            } else if (type == SQLITE_BLOB) {
                size_t const data_size = sqlite3_column_bytes(stmt, column_idx);
                const void *data = sqlite3_column_blob(stmt, column_idx);
                return db::column_value{data, data_size};
            } else if (type == SQLITE_TEXT) {
                std::string text = (const char *)sqlite3_column_text(stmt, column_idx);
                return db::column_value{text};
            }
        }
    }

    return db::column_value{nullptr};
}

db::column_value db::result_set::column_value(std::string const column_name) const {
    if (auto index_result = column_index(column_name)) {
        return column_value(index_result.value());
    }
    return db::column_value{nullptr};
}

db::column_map db::result_set::column_map() const {
    auto *const stmt = impl_ptr<impl>()->statement().stmt().value();
    int const column_count = sqlite3_data_count(stmt);

    db::column_map map;
    map.reserve(column_count);

    for (int idx = 0; idx < column_count; ++idx) {
        map.insert(std::make_pair(sqlite3_column_name(stmt, idx), column_value(idx)));
    }

    return map;
}

#pragma mark - private

void db::result_set::_close() {
    impl_ptr<impl>()->close();
}

void db::result_set::_set_database(database const &database) {
    impl_ptr<impl>()->set_database(database);
}
