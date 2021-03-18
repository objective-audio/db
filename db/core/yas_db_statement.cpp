//
//  yas_db_statement.cpp
//

#include "yas_db_statement.h"

using namespace yas;
using namespace yas::db;

#pragma mark - statement

statement::statement() = default;

statement::~statement() {
    this->close();
}

uintptr_t statement::identifier() const {
    return reinterpret_cast<uintptr_t>(this);
}

void statement::set_stmt(sqlite3_stmt *const stmt) {
    this->_stmt = stmt;
}

sqlite3_stmt *statement::stmt() const {
    return this->_stmt;
}

void statement::set_query(std::string query) {
    this->_query = std::move(query);
}

std::string const &statement::query() const {
    return this->_query;
}

void statement::set_in_use(bool const in_use) {
    this->_in_use = in_use;
}

bool statement::in_use() const {
    return this->_in_use;
}

void statement::reset() {
    if (this->_stmt) {
        sqlite3_reset(this->_stmt);
    }

    this->_in_use = false;
}

void statement::close() {
    if (this->_stmt) {
        sqlite3_finalize(this->_stmt);
        this->_stmt = nullptr;
    }

    this->_in_use = false;
}

statement_ptr statement::make_shared() {
    return statement_ptr(new statement{});
}
