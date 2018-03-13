//
//  yas_db_attribute.h
//

#pragma once

#include "yas_db_value.h"

namespace yas::db {
class attribute_args;

struct attribute {
    std::string const name;
    std::string const type;
    db::value const default_value;
    bool const not_null;
    bool const primary;
    bool const unique;

    attribute(attribute_args);

    std::string sql() const;

    static db::attribute const &id_attribute();
    static db::attribute const &object_id_attribute();
    static db::attribute const &save_id_attribute();
    static db::attribute const &action_attribute();
};
}
