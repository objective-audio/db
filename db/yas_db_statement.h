//
//  yas_db_statement.h
//

#pragma once

#include <sqlite3.h>
#include <memory>
#include <string>
#include "yas_base.h"
#include "yas_db_protocol.h"

namespace yas {
namespace db {
    class statement : public base {
        class impl;

       public:
        statement();
        statement(std::nullptr_t);

        ~statement();

        statement(statement const &) = default;
        statement(statement &&) = default;
        statement &operator=(statement const &) = default;
        statement &operator=(statement &&) = default;

        void set_stmt(sqlite3_stmt *const);
        sqlite3_stmt *stmt() const;

        void set_query(std::string);
        std::string const &query() const;

        void set_in_use(bool const);
        bool in_use() const;

        void reset();

        db::closable &closable();

       private:
        db::closable _closable = nullptr;
    };
}
}

template <>
struct std::hash<yas::db::statement> {
    std::size_t operator()(yas::db::statement const &key) const {
        return std::hash<uintptr_t>()(key.identifier());
    }
};
