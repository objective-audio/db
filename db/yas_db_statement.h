//
//  yas_db_statement.h
//

#pragma once

#include <sqlite3.h>
#include <memory>
#include <string>
#include "yas_base.h"
#include "yas_db_protocol.h"
#include "yas_property.h"

namespace yas {
namespace db {
    class statement : public base, public closable {
        using super_class = base;

       public:
        statement();
        statement(std::nullptr_t);

        ~statement();

        statement(statement const &) = default;
        statement(statement &&) = default;
        statement &operator=(statement const &) = default;
        statement &operator=(statement &&) = default;

        property<sqlite3_stmt *> &stmt();
        const property<sqlite3_stmt *> &stmt() const;

        property<std::string> &query();
        const property<std::string> &query() const;

        property<bool> &in_use();
        const property<bool> &in_use() const;

        void reset();

       private:
        class impl;

        void _close() override;
    };
}
}

template <>
struct std::hash<yas::db::statement> {
    std::size_t operator()(yas::db::statement const &key) const {
        return std::hash<uintptr_t>()(key.identifier());
    }
};
