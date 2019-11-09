//
//  yas_db_statement.cpp
//

#include "yas_db_statement.h"

using namespace yas;

#pragma mark - statement

db::statement::statement() = default;

db::statement::~statement() {
    this->close();
}

uintptr_t db::statement::identifier() const {
    return reinterpret_cast<uintptr_t>(this);
}

void db::statement::set_stmt(sqlite3_stmt *const stmt) {
    this->_stmt = stmt;
}

sqlite3_stmt *db::statement::stmt() const {
    return this->_stmt;
}

void db::statement::set_query(std::string query) {
    this->_query = std::move(query);
}

std::string const &db::statement::query() const {
    return this->_query;
}

void db::statement::set_in_use(bool const in_use) {
    this->_in_use = in_use;
}

bool db::statement::in_use() const {
    return this->_in_use;
}

void db::statement::reset() {
    if (this->_stmt) {
        sqlite3_reset(this->_stmt);
    }

    this->_in_use = false;
}

void db::statement::close() {
    if (this->_stmt) {
        sqlite3_finalize(this->_stmt);
        this->_stmt = nullptr;
    }

    this->_in_use = false;
}

db::statement_ptr db::statement::make_shared() {
    return statement_ptr(new statement{});
}
