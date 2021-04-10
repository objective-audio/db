//
//  yas_db_error.h
//

#pragma once

#include <db/yas_db_result_code.h>
#include <sqlite3.h>

namespace yas::db {
struct sqlite_result_code : result_code {
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

struct error final {
    error(std::nullptr_t);
    explicit error(db::error_type const type);
    error(db::error_type const type, db::sqlite_result_code const &code);
    error(db::error_type const type, db::sqlite_result_code const &code, std::string message);

    explicit operator bool() const;

    [[nodiscard]] db::error_type const &type() const;
    [[nodiscard]] db::sqlite_result_code const &code() const;
    [[nodiscard]] std::string const &message() const;

   private:
    db::error_type _type;
    db::sqlite_result_code _code;
    std::string _message;
};
}  // namespace yas::db

namespace yas {
std::string to_string(db::error_type const &);
std::string to_string(db::error const &);
}  // namespace yas
