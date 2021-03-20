//
//  yas_db_object_event.h
//

#pragma once

#include <db/yas_db_additional_types.h>

namespace yas::db {
enum class object_event_type {
    fetched,
    loaded,
    cleared,
    attribute_updated,
    relation_inserted,
    relation_removed,
    relation_replaced,
    erased,
};

class object_fetched_event;
class object_loaded_event;
class object_cleared_event;
class object_attribute_updated_event;
class object_relation_inserted_event;
class object_relation_removed_event;
class object_relation_replaced_event;
class object_erased_event;

struct object_event {
    object_event_type type() const;

    bool is_changed() const;
    bool is_erased() const;

    db::object_ptr const &object() const;
    db::object_id const &object_id() const;
    std::string const &name() const;
    std::string const &entity_name() const;
    std::vector<std::size_t> const &indices() const;
    db::value const &value() const;

    static object_event make_fetched(db::object_ptr const &object);
    static object_event make_loaded(db::object_ptr const &object);
    static object_event make_cleared(db::object_ptr const &object);
    static object_event make_attribute_updated(db::object_ptr const &object, std::string const &name,
                                               db::value const &value);
    static object_event make_relation_inserted(db::object_ptr const &object, std::string const &name,
                                               std::vector<std::size_t> &&indices);
    static object_event make_relation_removed(db::object_ptr const &object, std::string const &name,
                                              std::vector<std::size_t> &&indices);
    static object_event make_relation_replaced(db::object_ptr const &object, std::string const &name);
    static object_event make_erased(std::string const &entity_name, db::object_id const &object_id);

   private:
    object_event_type const _type;
    db::object_ptr const &_object;
    db::object_id const &_object_id;
    std::string const &_name;
    std::string const &_entity_name;
    std::vector<std::size_t> const &_indices;
    db::value const &_value;

    object_event(object_event_type const, object_ptr const &, db::object_id const &, std::string const &name,
                 std::string const &entity_name, std::vector<std::size_t> const &indices, db::value const &);
    object_event(object_relation_inserted_event &&);
    object_event(object_relation_removed_event &&);
    object_event(object_relation_replaced_event &&);
    object_event(object_erased_event &&);
};
}  // namespace yas::db
