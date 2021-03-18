//
//  yas_db_error.cpp
//

#include "yas_db_error.h"

using namespace yas;
using namespace yas::db;

#pragma mark - sqlite_result_code

db::sqlite_result_code::sqlite_result_code(int const &value) : result_code(value) {
}

db::sqlite_result_code::operator bool() const {
    int value = this->raw_value();
    return value == SQLITE_OK || value == SQLITE_DONE;
}

#pragma mark - error

error::error(error_type const type) : error(type, SQLITE_OK) {
}

error::error(error_type const type, db::sqlite_result_code const &code) : error(type, code, "") {
}

error::error(std::nullptr_t) : _type(error_type::none), _code(SQLITE_OK), _message() {
}

error::error(error_type const type, db::sqlite_result_code const &code, std::string message)
    : _type(type), _code(code), _message(std::move(message)) {
}

error::operator bool() const {
    return this->_type != error_type::none;
}

error_type const &error::type() const {
    return this->_type;
}

db::sqlite_result_code const &error::code() const {
    return this->_code;
}

std::string const &error::message() const {
    return this->_message;
}

#pragma mark -

std::string yas::to_string(error_type const &error_type) {
    switch (error_type) {
        case error_type::closed:
            return "closed";
        case error_type::in_use:
            return "in_use";
        case error_type::invalid_query_count:
            return "invalid_query_count";
        case error_type::invalid_argument:
            return "invalid_argument";
        case error_type::sqlite:
            return "sqlite";
        case error_type::none:
            return "none";
    }
}

std::string yas::to_string(error const &error) {
    if (error) {
        return "{type:" + to_string(error.type()) + ", code:" + to_string(error.code()) +
               ", message:" + error.message() + "}";
    } else {
        return "null";
    }
}
