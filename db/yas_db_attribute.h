//
//  yas_db_attribute.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "yas_db_value.h"

namespace yas {
namespace db {
    static std::string const id_field = "id";
    static std::string const object_id_field = "obj_id";
    static std::string const save_id_field = "save_id";
    static std::string const action_field = "action";

    static std::string const insert_action = "insert";
    static std::string const update_action = "update";
    static std::string const remove_action = "remove";

    struct attribute {
        std::string const name;
        std::string const type;
        bool const not_null;
        value const default_value;
        bool const primary;
        bool const unique;

        attribute(std::string const &name, std::string const &type, value const &default_value = nullptr,
                  bool const not_null = false, bool const primary = false, bool const unique = false);
        attribute(std::string const &name, CFDictionaryRef const dict);

        std::string sql() const;

        static attribute const &id_attribute();
        static attribute const &object_id_attribute();
        static attribute const &save_id_attribute();
        static attribute const &action_attribute();
    };
}
}
