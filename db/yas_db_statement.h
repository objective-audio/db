//
//  yas_db_statement.h
//

#pragma once

#include <sqlite3.h>
#include <memory>
#include <string>
#include "yas_db_protocol.h"

namespace yas::db {
struct statement final : closable {
    ~statement() = default;

    statement(statement const &) = default;
    statement(statement &&) = default;
    statement &operator=(statement const &) = default;
    statement &operator=(statement &&) = default;

    uintptr_t identifier() const;

    void set_stmt(sqlite3_stmt *const);
    sqlite3_stmt *stmt() const;

    void set_query(std::string);
    std::string const &query() const;

    void set_in_use(bool const);
    bool in_use() const;

    void reset();

    static statement_ptr make_shared();

   private:
    class impl;

    std::shared_ptr<impl> _impl;

    statement();

    void close() override;
};
}  // namespace yas::db
