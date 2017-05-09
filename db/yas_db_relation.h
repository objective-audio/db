//
//  yas_db_relation.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <string>

namespace yas {
namespace db {
    class entity;

    class relation {
       public:
        std::string const entity_name;
        std::string const name;
        std::string const target_entity_name;
        bool const many;

        std::string const table_name;

        relation(std::string const &entity_name, std::string const &name, CFDictionaryRef const &dict);

        std::string sql_for_create() const;
        std::string sql_for_insert() const;
    };
}
}
