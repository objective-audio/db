//
//  yas_db_attribute.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "yas_db_value.h"

namespace yas {
namespace db {
    struct attribute {
        std::string const name;
        std::string const type;
        bool const not_null;
        db::value const default_value;
        bool const primary;
        bool const unique;

        attribute(std::string const &name, std::string const &type, db::value const &default_value = nullptr,
                  bool const not_null = false, bool const primary = false, bool const unique = false);

        std::string sql() const;

        static db::attribute const &id_attribute();
        static db::attribute const &object_id_attribute();
        static db::attribute const &save_id_attribute();
        static db::attribute const &action_attribute();
    };

    db::attribute make_attribute(std::string const &name, CFDictionaryRef const dict);
}
}
