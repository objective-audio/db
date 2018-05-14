//
//  yas_db_object_utils.h
//

#pragma once

#include "yas_db_object.h"

namespace yas::db {
std::vector<db::const_object> get_const_relation_objects(db::const_object const &object,
                                                         db::const_object_map_map_t const &objects,
                                                         std::string const &rel_name);
db::const_object get_const_relation_object(db::const_object const &object, db::const_object_map_map_t const &objects,
                                           std::string const &rel_name, std::size_t const idx);
}  // namespace yas::db

namespace yas {
db::object_map_map_t to_object_map_map(db::object_vector_map_t vec);
db::object_map_t to_object_map(db::object_vector_t vec);
}  // namespace yas
