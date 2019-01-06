//
//  yas_db_object_utils.cpp
//

#include "yas_db_object_utils.h"
#include <cpp_utils/yas_stl_utils.h>
#include "yas_db_entity.h"
#include "yas_db_model.h"
#include "yas_db_relation.h"

using namespace yas;

std::vector<db::const_object> db::get_const_relation_objects(db::const_object const &object,
                                                             db::const_object_map_map_t const &objects,
                                                             std::string const &rel_name) {
    auto const rel_ids = object.relation_ids(rel_name);
    std::string const &tgt_entity_name = object.entity().relations.at(rel_name).target;

    if (objects.count(tgt_entity_name) > 0) {
        auto const &entity_objects = objects.at(tgt_entity_name);
        return to_vector<db::const_object>(
            rel_ids, [&entity_objects, entity_name = object.entity_name()](db::object_id const &rel_id) {
                db::integer::type const &stable = rel_id.stable();
                if (entity_objects.count(stable) > 0) {
                    return entity_objects.at(stable);
                }
                return db::null_const_object();
            });
    }

    return {};
}

db::const_object db::get_const_relation_object(db::const_object const &object,
                                               db::const_object_map_map_t const &objects, std::string const &rel_name,
                                               std::size_t const idx) {
    db::integer::type const &rel_id = object.relation_ids(rel_name).at(idx).stable();
    std::string const &tgt_entity_name = object.entity().relations.at(rel_name).target;

    if (objects.count(tgt_entity_name) > 0) {
        auto const &entity_objects = objects.at(tgt_entity_name);
        if (entity_objects.count(rel_id) > 0) {
            return entity_objects.at(rel_id);
        }
    }

    return db::null_const_object();
}

db::object_map_map_t yas::to_object_map_map(db::object_vector_map_t objects_vector) {
    db::object_map_map_t objects_map;

    for (auto &entity_pair : objects_vector) {
        std::string const &entity_name = entity_pair.first;
        auto entity_objects = to_object_map(std::move(entity_pair.second));
        objects_map.emplace(entity_name, std::move(entity_objects));
    }

    objects_vector.clear();

    return objects_map;
}

db::object_map_t yas::to_object_map(db::object_vector_t vec) {
    db::object_map_t map;

    auto it = vec.begin();
    auto end = vec.end();
    while (it != end) {
        db::object &obj = *it;
        db::integer::type obj_id = obj.object_id().stable();
        map.emplace(std::move(obj_id), std::move(obj));
        ++it;
    }

    vec.clear();

    return map;
}
