//
//  yas_db_attribute.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "yas_db_value.h"

namespace yas {
namespace db {
    static std::string const id_field = "id";

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

        static attribute id_attribute();

       private:
    };
}
}
