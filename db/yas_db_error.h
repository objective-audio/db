//
//  yas_db_error.h
//

#pragma once

#include <sqlite3.h>
#include "yas_db_result_code.h"

namespace yas {
namespace db {
    struct sqlite_result_code : public result_code {
        sqlite_result_code(int const &code = SQLITE_OK);

        explicit operator bool() const;
    };

    enum class error_type {
        none,
        closed,
        in_use,
        invalid_query_count,
        invalid_argument,
        sqlite,
    };

    struct error {
        error(std::nullptr_t);
        explicit error(db::error_type const type, db::sqlite_result_code const &code = 0, std::string message = "");

        explicit operator bool() const;

        db::error_type const &type() const;
        db::sqlite_result_code const &code() const;
        std::string const &message() const;

       private:
        db::error_type _type;
        db::sqlite_result_code _code;
        std::string _message;
    };
}
std::string to_string(db::error_type const &);
std::string to_string(db::error const &);
}
