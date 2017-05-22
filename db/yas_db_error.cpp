//
//  yas_db_error.cpp
//

#include "yas_db_error.h"

using namespace yas;

#pragma mark - sqlite_result_code

db::sqlite_result_code::sqlite_result_code(int const &value) : result_code(value) {
}

db::sqlite_result_code::operator bool() const {
    auto value = this->raw_value();
    return value == SQLITE_OK || value == SQLITE_DONE;
}

#pragma mark - error

db::error::error(std::nullptr_t) : _type(db::error_type::none), _code(0), _message() {
}

db::error::error(db::error_type const type, db::sqlite_result_code const &code, std::string message)
    : _type(type), _code(code), _message(std::move(message)) {
}

db::error::operator bool() const {
    return this->_type != db::error_type::none;
}

db::error_type const &db::error::type() const {
    return this->_type;
}

db::sqlite_result_code const &db::error::code() const {
    return this->_code;
}

std::string const &db::error::message() const {
    return this->_message;
}

#pragma mark -

std::string yas::to_string(db::error_type const &error_type) {
    switch (error_type) {
        case db::error_type::closed:
            return "closed";
        case db::error_type::in_use:
            return "in_use";
        case db::error_type::invalid_query_count:
            return "invalid_query_count";
        case db::error_type::invalid_argument:
            return "invalid_argument";
        case db::error_type::sqlite:
            return "sqlite";
        case db::error_type::none:
            return "none";
    }
    return std::string();
}
