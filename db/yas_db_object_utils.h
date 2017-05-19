//
//  yas_db_object_utils.h
//

#pragma once

#include "yas_db_object.h"

namespace yas {
namespace db {
    std::vector<const_object> get_const_relation_objects(const_object const &object,
                                                         const_object_map_map_t const &objects,
                                                         std::string const &rel_name);
    db::const_object get_const_relation_object(const_object const &object, const_object_map_map_t const &objects,
                                               std::string const &rel_name, std::size_t const idx);

    template <typename T>
    db::integer_set_map_t relation_ids(T const &objects) {
        db::integer_set_map_t rel_ids;

        for (auto const &entity_pair : objects) {
            for (auto const &object : entity_pair.second) {
                auto obj_rel_ids = object.relation_ids_for_fetch();
                for (auto &obj_rel_pair : obj_rel_ids) {
                    auto const &entity_name = obj_rel_pair.first;
                    if (rel_ids.count(entity_name) == 0) {
                        rel_ids.emplace(entity_name, db::integer_set_t{});
                    }

                    for (auto &tgt_obj_id : obj_rel_pair.second) {
                        rel_ids.at(entity_name).emplace(tgt_obj_id);
                    }
                }
            }
        }

        return rel_ids;
    }
}
db::object_map_map_t to_object_map_map(db::object_vector_map_t vec);
db::object_map_t to_object_map(db::object_vector_t vec);
}
