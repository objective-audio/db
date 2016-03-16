//
//  yas_db_row_set.cpp
//

#include <vector>
#include "yas_db_database.h"
#include "yas_db_row_set.h"
#include "yas_db_statement.h"
#include "yas_db_value.h"
#include "yas_each_index.h"
#include "yas_stl_utils.h"

using namespace yas;

#pragma mark - code

db::next_result_code::next_result_code(int const &value) : result_code(value) {
}

db::next_result_code::operator bool() const {
    return raw_value() == SQLITE_ROW;
}

#pragma mark - impl

class db::row_set::impl : public base::impl, public closable::impl, public db_settable::impl {
   public:
    impl(db::statement const &statement, database const &database) : _statement(statement), _database(database) {
        _statement.in_use().set_value(true);
    }

    ~impl() {
        close();
    }

    void close() override {
        _statement.reset();
        if (_database) {
            if (auto observable_db = _database.row_set_observable()) {
                observable_db.row_set_did_close(identifier());
            }
            _database = nullptr;
        }
    }

    void _set_database(database const &database) override {
        _database = database;
    }

    database const &database() const {
        return _database;
    }

    db::statement const &statement() const {
        return _statement;
    }

    std::unordered_map<std::string, int> const &column_name_to_index_map() const {
        if (_column_name_to_index_map.empty()) {
            auto *const stmt = _statement.stmt().value();
            int column_count = sqlite3_column_count(stmt);
            for (auto &idx : make_each(column_count)) {
                _column_name_to_index_map.insert(std::make_pair(to_lower(sqlite3_column_name(stmt, idx)), idx));
            }
        }

        return _column_name_to_index_map;
    }

   private:
    db::database _database;
    db::statement _statement;

    mutable std::unordered_map<std::string, int> _column_name_to_index_map;
};

db::row_set::row_set(db::statement const &statement, database const &database)
    : super_class(std::make_unique<impl>(statement, database)) {
}

db::row_set::row_set(std::nullptr_t) : super_class(nullptr) {
}

db::row_set::~row_set() = default;

db::statement const &db::row_set::statement() const {
    return impl_ptr<impl>()->statement();
}

db::next_result_code db::row_set::next() {
    auto result = next_result_code(sqlite3_step(impl_ptr<impl>()->statement().stmt().value()));

    if (!result) {
        impl_ptr<impl>()->close();
    }

    return result;
}

bool db::row_set::has_row() {
    if (auto const database = impl_ptr<impl>()->database()) {
        if (auto const sqlite_handle = database.sqlite_handle()) {
            return sqlite3_errcode(sqlite_handle) == SQLITE_ROW;
        }
    }
    return false;
}

int db::row_set::column_count() const {
    return sqlite3_column_count(impl_ptr<impl>()->statement().stmt().value());
}

db::row_set::index_result db::row_set::column_index(std::string column_name) const {
    std::string lower_column_name = to_lower(std::move(column_name));

    auto const &map = impl_ptr<impl>()->column_name_to_index_map();

    if (map.count(lower_column_name) > 0) {
        return index_result{map.at(lower_column_name)};
    }

    return index_result{nullptr};
}

std::string db::row_set::column_name(int const column_idx) const {
    return sqlite3_column_name(impl_ptr<impl>()->statement().stmt().value(), column_idx);
}

bool db::row_set::column_is_null(int const column_idx) {
    return sqlite3_column_type(impl_ptr<impl>()->statement().stmt().value(), column_idx) == SQLITE_NULL;
}

bool db::row_set::column_is_null(std::string column_name) {
    if (auto const index_result = column_index(std::move(column_name))) {
        return column_is_null(index_result.value());
    }
    return true;
}

db::value db::row_set::column_value(int const column_idx) const {
    if (column_idx >= 0) {
        auto *const stmt = impl_ptr<impl>()->statement().stmt().value();
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

    return db::value{nullptr};
}

db::value db::row_set::column_value(std::string column_name) const {
    if (auto index_result = column_index(std::move(column_name))) {
        return column_value(index_result.value());
    }
    return db::value{nullptr};
}

db::value_map db::row_set::value_map() const {
    auto *const stmt = impl_ptr<impl>()->statement().stmt().value();
    int const column_count = sqlite3_data_count(stmt);

    db::value_map map;
    map.reserve(column_count);

    for (auto &idx : make_each(column_count)) {
        map.insert(std::make_pair(sqlite3_column_name(stmt, idx), column_value(idx)));
    }

    return map;
}

db::closable db::row_set::closable() {
    return db::closable{impl_ptr<closable::impl>()};
}

db::db_settable db::row_set::db_settable() {
    return db::db_settable{impl_ptr<db_settable::impl>()};
}
