//
//  yas_db_entity.h
//

#pragma once

#include <string>
#include <unordered_map>
#include "yas_db_additional_protocol.h"

namespace yas::db {
struct entity {
    std::string const name;
    db::attribute_map_t const all_attributes;
    db::attribute_map_t const custom_attributes;
    db::relation_map_t const relations;
    db::string_set_map_t const inverse_relation_names;

    explicit entity(entity_args, db::string_set_map_t inv_rel_names);

    std::string sql_for_create() const;
    std::string sql_for_update() const;
    std::string sql_for_insert() const;
};
}
