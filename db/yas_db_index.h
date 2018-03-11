//
//  yas_db_index.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <string>
#include <vector>

namespace yas::db {
class index {
   public:
    struct args {
        std::string name;
        std::string table_name;
        std::vector<std::string> attribute_names;
    };

    std::string const name;
    std::string const table_name;
    std::vector<std::string> const attribute_names;

    explicit index(args);
    index(std::string const &name, std::string const &table_name, std::vector<std::string> const &attr_names);
    index(std::string const &name, CFDictionaryRef const dict);

    std::string sql_for_create() const;
};
}
