//
//  yas_db_entity.h
//

#pragma once

#include <string>
#include <unordered_map>

namespace yas {
namespace db {
    class attribute;
    class relation;

    using attribute_map = std::unordered_map<std::string, attribute>;
    using relation_map = std::unordered_map<std::string, relation>;

    struct entity {
        std::string const name;
        db::attribute_map const attributes;
        db::relation_map const relations;

        entity(std::string const &name, db::attribute_map &&attributes, db::relation_map &&relations);

        std::string sql_for_create() const;
        std::string sql_for_update() const;
        std::string sql_for_insert() const;
    };
}
}
