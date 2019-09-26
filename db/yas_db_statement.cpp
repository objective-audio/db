//
//  yas_db_statement.cpp
//

#include "yas_db_statement.h"

using namespace yas;

#pragma mark - statement::impl

struct db::statement::impl {
    ~impl() {
        this->close();
    }

    uintptr_t identifier() {
        return reinterpret_cast<uintptr_t>(this);
    }

    void close() {
        if (this->_stmt) {
            sqlite3_finalize(this->_stmt);
            this->_stmt = nullptr;
        }

        this->_in_use = false;
    }

    void reset() {
        if (this->_stmt) {
            sqlite3_reset(this->_stmt);
        }

        this->_in_use = false;
    }

    sqlite3_stmt *_stmt;
    std::string _query;
    bool _in_use = false;
};

#pragma mark - statement

db::statement::statement() : _impl(std::make_unique<impl>()) {
}

uintptr_t db::statement::identifier() const {
    return this->_impl->identifier();
}

void db::statement::set_stmt(sqlite3_stmt *const stmt) {
    this->_impl->_stmt = stmt;
}

sqlite3_stmt *db::statement::stmt() const {
    return this->_impl->_stmt;
}

void db::statement::set_query(std::string query) {
    this->_impl->_query = std::move(query);
}

std::string const &db::statement::query() const {
    return this->_impl->_query;
}

void db::statement::set_in_use(bool const in_use) {
    this->_impl->_in_use = in_use;
}

bool db::statement::in_use() const {
    return this->_impl->_in_use;
}

void db::statement::reset() {
    this->_impl->reset();
}

void db::statement::close() {
    this->_impl->close();
}

db::statement_ptr db::statement::make_shared() {
    return statement_ptr(new statement{});
}
