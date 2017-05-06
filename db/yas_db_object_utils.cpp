//
//  yas_db_object_utils.cpp
//

#include "yas_db_model.h"
#include "yas_db_object_utils.h"
#include "yas_stl_utils.h"

using namespace yas;

std::vector<db::const_object> db::get_const_relation_objects(const_object const &object,
                                                             const_object_map_map_t const &objects,
                                                             std::string const &rel_name) {
    auto const rel_ids = object.relation_ids(rel_name);
    std::string const &tgt_entity_name = object.model().relation(object.entity_name(), rel_name).target_entity_name;

    if (objects.count(tgt_entity_name) > 0) {
        auto const &entity_objects = objects.at(tgt_entity_name);
        return to_vector<db::const_object>(rel_ids,
                                           [&entity_objects, entity_name = object.entity_name()](db::value const &id) {
                                               if (entity_objects.count(id.get<integer>()) > 0) {
                                                   return entity_objects.at(id.get<integer>());
                                               }
                                               return db::const_object::null_object();
                                           });
    }

    return {};
}

db::const_object db::get_const_relation_object(const_object const &object, const_object_map_map_t const &objects,
                                               std::string const &rel_name, std::size_t const idx) {
    auto const rel_id = object.relation_ids(rel_name).at(idx).get<integer>();
    std::string const &tgt_entity_name = object.model().relation(object.entity_name(), rel_name).target_entity_name;

    if (objects.count(tgt_entity_name) > 0) {
        auto const &entity_objects = objects.at(tgt_entity_name);
        if (entity_objects.count(rel_id) > 0) {
            return entity_objects.at(rel_id);
        }
    }

    return db::const_object::null_object();
}

db::object_map_map_t yas::to_object_map_map(db::object_vector_map_t objects_vector) {
    db::object_map_map_t objects_map;

    for (auto &entity_pair : objects_vector) {
        auto &entity_name = entity_pair.first;
        auto entity_objects = to_object_map(std::move(entity_pair.second));
        objects_map.emplace(std::make_pair(entity_name, std::move(entity_objects)));
    }

    objects_vector.clear();

    return objects_map;
}

db::object_map_t yas::to_object_map(db::object_vector_t vec) {
    db::object_map_t map;

    auto it = vec.begin();
    auto end = vec.end();
    while (it != end) {
        auto &obj = *it;
        auto obj_id = obj.object_id().get<db::integer>();
        map.emplace(std::make_pair(std::move(obj_id), std::move(obj)));
        ++it;
    }

    vec.clear();

    return map;
}
