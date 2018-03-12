//
//  yas_db_index.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <string>
#include <vector>

namespace yas::db {
class index_args;

class index {
   public:
    std::string const name;
    std::string const entity;
    std::vector<std::string> const attribute_names;

    explicit index(index_args);
    index(std::string const &name, CFDictionaryRef const dict);

    std::string sql_for_create() const;
};
}
