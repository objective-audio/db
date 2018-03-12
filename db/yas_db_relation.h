//
//  yas_db_relation.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <string>

namespace yas::db {
class relation_args;

struct relation {
   public:
    std::string const name;
    std::string const source;
    std::string const target;
    bool const many;

    std::string const table;

    explicit relation(relation_args, std::string source);
    relation(std::string const &src_entity_name, std::string const &name, CFDictionaryRef const &dict);

    std::string sql_for_create() const;
    std::string sql_for_insert() const;
};
}
