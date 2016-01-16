//
//  yas_db_row_set.h
//

#pragma once

#include <string>
#include "yas_base.h"
#include "yas_db_protocol.h"
#include "yas_db_result_code.h"
#include "yas_db_value.h"
#include "yas_property.h"
#include "yas_result.h"

namespace yas {
namespace db {
    class database;
    class statement;
    class value;

    struct next_result_code : public result_code {
        next_result_code(int const &value);

        explicit operator bool() const;
    };

    class row_set : public base, public closable, public db_holdable {
        using super_class = base;

       public:
        class impl;

        using index_result = result<int, std::nullptr_t>;

        row_set(statement const &, database const &);
        row_set(std::nullptr_t);

        ~row_set();

        bool operator==(std::nullptr_t) const;
        bool operator!=(std::nullptr_t) const;

        statement const &statement() const;

        next_result_code next();
        bool has_row();

        int column_count() const;
        index_result column_index(std::string const &column_name) const;
        std::string column_name(int const column_idx) const;
        bool column_is_null(int const column_idx);
        bool column_is_null(std::string const column_name);

        db::value column_value(int const column_idx) const;
        db::value column_value(std::string const column_name) const;

        db::value_map value_map() const;

       private:
        void _close() override;
        void _set_database(database const &) override;
    };
}
}

template <>
struct std::hash<yas::db::row_set> {
    std::size_t operator()(yas::db::row_set const &key) const {
        return std::hash<uintptr_t>()(key.identifier());
    }
};

template <>
struct std::hash<yas::weak<yas::db::row_set>> {
    std::size_t operator()(yas::weak<yas::db::row_set> const &key) const {
        return std::hash<uintptr_t>()(key.identifier());
    }
};
