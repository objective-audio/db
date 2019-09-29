//
//  yas_db_object.h
//

#pragma once

#include <chaining/yas_chaining_umbrella.h>
#include <deque>
#include <set>
#include <unordered_map>
#include "yas_db_additional_protocol.h"

namespace yas::db {
class entity;

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

   private:
    std::shared_ptr<impl_base> _impl;
};

struct const_object {
    class impl;

    db::entity const &entity() const;
    std::string const &entity_name() const;

    db::value const &attribute_value(std::string const &attr_name) const;

    db::id_vector_map_t const &all_relation_ids() const;
    db::id_vector_t relation_ids(std::string const &rel_name) const;
    db::object_id const &relation_id(std::string const &rel_name, std::size_t const idx) const;
    std::size_t relation_size(std::string const &rel_name) const;

    db::object_id const &object_id() const;
    db::value const &save_id() const;
    db::value const &action() const;

    bool is_inserted() const;
    bool is_updated() const;
    bool is_removed() const;

    bool operator==(const_object const &rhs) const;
    bool operator!=(const_object const &rhs) const;

    explicit operator bool() const;

    static const_object_ptr make_shared(db::entity const &entity, db::object_data const &obj_data);

   protected:
    std::shared_ptr<impl> _impl;

    const_object(db::entity const &entity, db::object_data const &obj_data);
    const_object(std::shared_ptr<impl> &&);
};

struct object final : const_object {
    class impl;

    [[nodiscard]] chaining::chain_sync_t<object_event> chain() const;

    void set_attribute_value(std::string const &attr_name, db::value const &value);

    void set_relation_ids(std::string const &rel_name, db::id_vector_t const &relation_ids);
    void add_relation_id(std::string const &rel_name, db::object_id const &relation_id);
    void insert_relation_id(std::string const &rel_name, db::object_id const &relation_id, std::size_t const idx);
    void remove_relation_id(std::string const &rel_name, db::object_id const &relation_id);
    void set_relation_objects(std::string const &rel_name, db::object_vector_t const &rel_objects);
    void add_relation_object(std::string const &rel_name, db::object_ptr const &rel_object);
    void insert_relation_object(std::string const &rel_name, db::object_ptr const &rel_object, std::size_t const idx);
    void remove_relation_object(std::string const &rel_name, db::object_ptr const &rel_object);
    void remove_relation_at(std::string const &rel_name, std::size_t const idx);
    void remove_all_relations(std::string const &rel_name);

    db::object_status status() const;

    void remove();

    bool is_temporary() const;

    db::object_data save_data(db::object_id_pool_t &) const;

    db::manageable_object &manageable();

    static object_ptr make_shared(db::entity const &);

   private:
    db::manageable_object _manageable = nullptr;

    object(db::entity const &entity);

    std::shared_ptr<impl> _mutable_impl() const;

    void _prepare(object_ptr const &);
};

db::value const &insert_action_value();
db::value const &update_action_value();
db::value const &remove_action_value();
}  // namespace yas::db

namespace yas {
std::string to_string(db::object_status const &);
}
