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

struct object_fetched_event {
    static object_event_type const type = object_event_type::fetched;
    db::object_ptr const &object;
};

struct object_loaded_event {
    static object_event_type const type = object_event_type::loaded;
    db::object_ptr const &object;
};

struct object_cleared_event {
    static object_event_type const type = object_event_type::cleared;
    db::object_ptr const &object;
};

struct object_attribute_updated_event {
    static object_event_type const type = object_event_type::attribute_updated;
    db::object_ptr const &object;
    std::string const name;
    db::value const &value;
};

struct object_relation_inserted_event {
    static object_event_type const type = object_event_type::relation_inserted;
    db::object_ptr const &object;
    std::string const name;
    std::vector<std::size_t> const indices;
};

struct object_relation_removed_event {
    static object_event_type const type = object_event_type::relation_removed;
    db::object_ptr const &object;
    std::string const name;
    std::vector<std::size_t> const indices;
};

struct object_relation_replaced_event {
    static object_event_type const type = object_event_type::relation_replaced;
    db::object_ptr const &object;
    std::string const name;
};

struct object_erased_event {
    static object_event_type const type = object_event_type::erased;
    std::string const &entity_name;
    db::object_id const &object_id;
};

struct object_event {
    class impl_base;

    template <typename Event>
    class impl;

    object_event(object_fetched_event &&);
    object_event(object_loaded_event &&);
    object_event(object_cleared_event &&);
    object_event(object_attribute_updated_event &&);
    object_event(object_relation_inserted_event &&);
    object_event(object_relation_removed_event &&);
    object_event(object_relation_replaced_event &&);
    object_event(object_erased_event &&);
    object_event(std::nullptr_t);

    object_event_type type() const;

    template <typename Event>
    Event const &get() const;

    bool is_changed() const;
    bool is_erased() const;

    db::object_ptr const &object() const;
    db::object_id const &object_id() const;
    std::string const &name() const;
    std::string const &entity_name() const;
    std::vector<std::size_t> const &indices() const;
    db::value const &value() const;

    static object_event make_fetched(db::object_ptr const &object);

   private:
    std::shared_ptr<impl_base> _impl;
};

object_event make_object_loaded_event(db::object_ptr const &object);
object_event make_object_cleared_event(db::object_ptr const &object);
object_event make_object_attribute_updated_event(db::object_ptr const &object, std::string const &name,
                                                 db::value const &value);
object_event make_object_relation_inserted_event(db::object_ptr const &object, std::string const &name,
                                                 std::vector<std::size_t> &&indices);
object_event make_object_relation_removed_event(db::object_ptr const &object, std::string const &name,
                                                std::vector<std::size_t> &&indices);
object_event make_object_relation_replaced_event(db::object_ptr const &object, std::string const &name);
object_event make_object_erased_event(std::string const &entity_name, db::object_id const &object_id);
}  // namespace yas::db
