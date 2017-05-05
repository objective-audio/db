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

    using attribute_map_t = std::unordered_map<std::string, attribute>;
    using relation_map_t = std::unordered_map<std::string, relation>;

    struct entity {
        std::string const name;
        db::attribute_map_t const attributes;
        db::attribute_map_t const custom_attributes;
        db::relation_map_t const relations;

        entity(std::string const &name, db::attribute_map_t &&attributes, db::relation_map_t &&relations);

        std::string sql_for_create() const;
        std::string sql_for_update() const;
        std::string sql_for_insert() const;
    };
}
}
