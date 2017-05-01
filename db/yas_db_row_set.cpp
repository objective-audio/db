//
//  yas_db_row_set.cpp
//

#include <vector>
#include "yas_db_database.h"
#include "yas_db_row_set.h"
#include "yas_db_statement.h"
#include "yas_db_value.h"
#include "yas_fast_each.h"
#include "yas_result.h"
#include "yas_stl_utils.h"

using namespace yas;

#pragma mark - code

db::next_result_code::next_result_code(int const &value) : result_code(value) {
}

db::next_result_code::operator bool() const {
    return this->raw_value() == SQLITE_ROW;
}

#pragma mark - impl

class db::row_set::impl : public base::impl, public closable::impl, public db_settable::impl {
   public:
    impl(db::statement const &statement, database const &database) : _statement(statement), _database(database) {
        this->_statement.set_in_use(true);
    }

    ~impl() {
        this->close();
    }

    void close() override {
        this->_statement.reset();
        if (this->_database) {
            if (auto observable_db = this->_database.row_set_observable()) {
                observable_db.row_set_did_close(identifier());
            }
            this->_database = nullptr;
        }
    }

    void _set_database(database const &database) override {
        this->_database = database;
    }

    database const &database() const {
        return this->_database;
    }

    db::statement const &statement() const {
        return this->_statement;
    }

    std::unordered_map<std::string, int> const &column_name_to_index_map() const {
        if (this->_column_name_to_index_map.empty()) {
            auto *const stmt = this->_statement.stmt();
            int column_count = sqlite3_column_count(stmt);
            auto each = make_fast_each(column_count);
            while (yas_each_next(each)) {
                auto const &idx = yas_each_index(each);
                this->_column_name_to_index_map.insert(std::make_pair(to_lower(sqlite3_column_name(stmt, idx)), idx));
            }
        }

        return this->_column_name_to_index_map;
    }

   private:
    db::database _database;
    db::statement _statement;

    mutable std::unordered_map<std::string, int> _column_name_to_index_map;
};

db::row_set::row_set(db::statement const &statement, database const &database)
    : base(std::make_unique<impl>(statement, database)) {
}

db::row_set::row_set(std::nullptr_t) : base(nullptr) {
}

db::row_set::~row_set() = default;

db::statement const &db::row_set::statement() const {
    return impl_ptr<impl>()->statement();
}

db::next_result_code db::row_set::next() {
    auto result = next_result_code(sqlite3_step(impl_ptr<impl>()->statement().stmt()));

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
    return sqlite3_column_count(impl_ptr<impl>()->statement().stmt());
}

db::row_set::index_result_t db::row_set::column_index(std::string column_name) const {
    std::string lower_column_name = to_lower(std::move(column_name));

    auto const &map = impl_ptr<impl>()->column_name_to_index_map();

    if (map.count(lower_column_name) > 0) {
        return db::row_set::index_result_t{map.at(lower_column_name)};
    }

    return db::row_set::index_result_t{nullptr};
}

std::string db::row_set::column_name(int const column_idx) const {
    return sqlite3_column_name(impl_ptr<impl>()->statement().stmt(), column_idx);
}

bool db::row_set::column_is_null(int const column_idx) {
    return sqlite3_column_type(impl_ptr<impl>()->statement().stmt(), column_idx) == SQLITE_NULL;
}

bool db::row_set::column_is_null(std::string column_name) {
    if (auto const index_result = column_index(std::move(column_name))) {
        return this->column_is_null(index_result.value());
    }
    return true;
}

db::value db::row_set::column_value(int const column_idx) const {
    if (column_idx >= 0) {
        auto *const stmt = impl_ptr<impl>()->statement().stmt();
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

    return db::value::null_value();
}

db::value db::row_set::column_value(std::string column_name) const {
    if (auto index_result = column_index(std::move(column_name))) {
        return this->column_value(index_result.value());
    }
    return db::value::null_value();
}

db::value_map_t db::row_set::value_map_t() const {
    auto *const stmt = impl_ptr<impl>()->statement().stmt();
    int const column_count = sqlite3_data_count(stmt);

    db::value_map_t map;
    map.reserve(column_count);

    auto each = make_fast_each(column_count);
    while (yas_each_next(each)) {
        auto const &idx = yas_each_index(each);
        map.insert(std::make_pair(sqlite3_column_name(stmt, idx), column_value(idx)));
    }

    return map;
}

db::closable &db::row_set::closable() {
    if (!this->_closable) {
        this->_closable = db::closable{impl_ptr<closable::impl>()};
    }
    return this->_closable;
}

db::db_settable &db::row_set::db_settable() {
    if (!this->_db_settable) {
        this->_db_settable = db::db_settable{impl_ptr<db_settable::impl>()};
    }
    return this->_db_settable;
}
