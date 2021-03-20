//
//  yas_db_object_event.cpp
//

#include "yas_db_object_event.h"

#include "yas_db_object.h"

using namespace yas;
using namespace yas::db;

namespace yas::db {
static db::object_ptr const _empty_object = nullptr;
static db::object_id const _empty_object_id = nullptr;
static std::string const _empty_string;
static std::vector<std::size_t> const _empty_indices;
static db::value const _empty_value = nullptr;

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
}  // namespace yas::db

object_event db::object_event::make_fetched(db::object_ptr const &object) {
    return object_event{object_event_type::fetched,
                        object,
                        _empty_object_id,
                        _empty_string,
                        _empty_string,
                        _empty_indices,
                        _empty_value};
}

object_event db::object_event::make_loaded(db::object_ptr const &object) {
    return object_event{object_loaded_event{.object = object}};
}

object_event db::object_event::make_cleared(db::object_ptr const &object) {
    return object_event{object_cleared_event{.object = object}};
}

object_event db::object_event::make_attribute_updated(db::object_ptr const &object, std::string const &name,
                                                      db::value const &value) {
    return object_event{object_attribute_updated_event{.object = object, .name = name, .value = value}};
}

object_event db::object_event::make_relation_inserted(db::object_ptr const &object, std::string const &name,
                                                      std::vector<std::size_t> &&indices) {
    return object_event{object_relation_inserted_event{.object = object, .name = name, .indices = std::move(indices)}};
}

object_event db::object_event::make_relation_removed(db::object_ptr const &object, std::string const &name,
                                                     std::vector<std::size_t> &&indices) {
    return object_event{object_relation_removed_event{.object = object, .name = name, .indices = std::move(indices)}};
}

object_event db::object_event::make_relation_replaced(db::object_ptr const &object, std::string const &name) {
    return object_event{object_relation_replaced_event{.object = object, .name = name}};
}

object_event db::object_event::make_erased(std::string const &entity_name, db::object_id const &object_id) {
    return object_event{object_erased_event{.entity_name = entity_name, .object_id = object_id}};
}

db::object_event::object_event(object_event_type const type, object_ptr const &object, db::object_id const &object_id,
                               std::string const &name, std::string const &entity_name,
                               std::vector<std::size_t> const &indices, db::value const &value)
    : _type(type),
      _object(object),
      _object_id(object_id),
      _name(name),
      _entity_name(entity_name),
      _indices(indices),
      _value(value) {
}

object_event::object_event(object_loaded_event &&event)
    : _type(object_event_type::loaded),
      _object(event.object),
      _object_id(_empty_object_id),
      _name(_empty_string),
      _entity_name(_empty_string),
      _indices(_empty_indices),
      _value(_empty_value) {
}

object_event::object_event(object_cleared_event &&event)
    : _type(object_event_type::cleared),
      _object(event.object),
      _object_id(_empty_object_id),
      _name(_empty_string),
      _entity_name(_empty_string),
      _indices(_empty_indices),
      _value(_empty_value) {
}

object_event::object_event(object_attribute_updated_event &&event)
    : _type(object_event_type::attribute_updated),
      _object(event.object),
      _object_id(_empty_object_id),
      _name(event.name),
      _entity_name(_empty_string),
      _indices(_empty_indices),
      _value(event.value) {
}

object_event::object_event(object_relation_inserted_event &&event)
    : _type(object_event_type::relation_inserted),
      _object(event.object),
      _object_id(_empty_object_id),
      _name(event.name),
      _entity_name(_empty_string),
      _indices(event.indices),
      _value(_empty_value) {
}

object_event::object_event(object_relation_removed_event &&event)
    : _type(object_event_type::relation_removed),
      _object(event.object),
      _object_id(_empty_object_id),
      _name(event.name),
      _entity_name(_empty_string),
      _indices(event.indices),
      _value(_empty_value) {
}

object_event::object_event(object_relation_replaced_event &&event)
    : _type(object_event_type::relation_replaced),
      _object(event.object),
      _object_id(_empty_object_id),
      _name(event.name),
      _entity_name(_empty_string),
      _indices(_empty_indices),
      _value(_empty_value) {
}

object_event::object_event(object_erased_event &&event)
    : _type(object_event_type::erased),
      _object(_empty_object),
      _object_id(event.object_id),
      _name(_empty_string),
      _entity_name(event.entity_name),
      _indices(_empty_indices),
      _value(_empty_value) {
}

object_event_type object_event::type() const {
    return this->_type;
}

bool object_event::is_changed() const {
    switch (this->type()) {
        case object_event_type::attribute_updated:
        case object_event_type::relation_inserted:
        case object_event_type::relation_removed:
        case object_event_type::relation_replaced:
            return true;
        default:
            return false;
    }
}

bool object_event::is_erased() const {
    return this->type() == object_event_type::erased;
}

db::object_ptr const &object_event::object() const {
    return this->_object;
}

db::object_id const &object_event::object_id() const {
    return this->_object_id;
}

std::string const &object_event::name() const {
    return this->_name;
}

std::string const &object_event::entity_name() const {
    return this->_entity_name;
}

std::vector<std::size_t> const &object_event::indices() const {
    return this->_indices;
}

db::value const &object_event::value() const {
    return this->_value;
}
