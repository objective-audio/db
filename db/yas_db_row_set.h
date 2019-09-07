//
//  yas_db_row_set.h
//

#pragma once

#include <string>
#include "yas_db_protocol.h"
#include "yas_db_ptr.h"
#include "yas_db_result_code.h"
#include "yas_db_types.h"

namespace yas {
template <typename T, typename U>
class result;
}

namespace yas::db {
class statement;
class value;

struct next_result_code : result_code {
    next_result_code(int const &value);

    explicit operator bool() const;
};

struct row_set {
    using index_result_t = result<int, std::nullptr_t>;

    ~row_set();

    uintptr_t identifier() const;

    db::statement_ptr const &statement() const;

    db::next_result_code next();
    bool has_row();

    int column_count() const;
    index_result_t column_index(std::string column_name) const;
    std::string column_name(int const column_idx) const;
    bool column_is_null(int const column_idx);
    bool column_is_null(std::string column_name);

    db::value column_value(int const column_idx) const;
    db::value column_value(std::string column_name) const;

    db::value_map_t values() const;

    db::closable &closable();
    db_settable &db_settable();

    static row_set_ptr make_shared(db::statement_ptr const &, database_ptr const &);

   private:
    class impl;
    std::shared_ptr<impl> _impl;
    db::closable _closable = nullptr;
    db::db_settable _db_settable = nullptr;

    row_set(db::statement_ptr const &, database_ptr const &);
};
}  // namespace yas::db
