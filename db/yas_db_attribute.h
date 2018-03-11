//
//  yas_db_attribute.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "yas_db_value.h"
#include "yas_db_additional_types.h"

namespace yas::db {
struct attribute {
    struct args {
        std::string name;
        attribute_type type;
        db::value default_value = nullptr;
        bool not_null = false;
        bool primary = false;
        bool unique = false;
    };

    std::string const name;
    std::string const type;
    db::value const default_value;
    bool const not_null;
    bool const primary;
    bool const unique;

    attribute(args);

    std::string sql() const;

    static db::attribute const &id_attribute();
    static db::attribute const &object_id_attribute();
    static db::attribute const &save_id_attribute();
    static db::attribute const &action_attribute();
};

db::attribute make_attribute(std::string const &name, CFDictionaryRef const dict);
}
