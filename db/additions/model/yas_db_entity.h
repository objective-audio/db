//
//  yas_db_entity.h
//

#pragma once

#include <db/yas_db_additional_protocol.h>

#include <string>
#include <unordered_map>

namespace yas::db {
struct entity final {
    std::string const name;
    db::attribute_map_t const all_attributes;
    db::attribute_map_t const custom_attributes;
    db::relation_map_t const relations;
    db::string_set_map_t const inverse_relation_names;

    entity(entity_args, db::string_set_map_t inv_rel_names);

    [[nodiscard]] std::string sql_for_create() const;
    [[nodiscard]] std::string sql_for_update() const;
    [[nodiscard]] std::string sql_for_insert() const;
};
}  // namespace yas::db
