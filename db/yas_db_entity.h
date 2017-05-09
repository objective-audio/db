//
//  yas_db_entity.h
//

#pragma once

#include <string>
#include <unordered_map>
#include <unordered_set>

namespace yas {
namespace db {
    class attribute;
    class relation;

    using attribute_map_t = std::unordered_map<std::string, attribute>;
    using relation_map_t = std::unordered_map<std::string, relation>;
    using string_set_t = std::unordered_set<std::string>;
    using string_set_map_t = std::unordered_map<std::string, string_set_t>;

    struct entity {
        std::string const name;
        db::attribute_map_t const all_attributes;
        db::attribute_map_t const custom_attributes;
        db::relation_map_t const relations;
        db::string_set_map_t const inverse_relation_names;

        entity(std::string const &name, db::attribute_map_t &&attributes, db::relation_map_t &&relations,
               db::string_set_map_t &&inv_rel_names);

        std::string sql_for_create() const;
        std::string sql_for_update() const;
        std::string sql_for_insert() const;
    };
}
}
