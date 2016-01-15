//
//  yas_db_entity.h
//

#pragma once

#include <string>
#include "yas_db_attribute.h"
#include "yas_db_relation.h"

namespace yas {
namespace db {
    using attributes_map = std::unordered_map<std::string, db::attribute>;
    using relations_map = std::unordered_map<std::string, db::relation>;

    struct entity {
        std::string const name;
        attributes_map const attributes;
        relations_map const relations;

        entity(std::string const &name, attributes_map &&attributes, relations_map &&relations);

        std::string sql_for_create() const;
        std::string sql_for_update() const;
        std::string sql_for_insert() const;
    };
}
}
