//
//  yas_db_object_event.cpp
//

#include "yas_db_object_event.h"

#include "yas_db_object.h"

using namespace yas;
using namespace yas::db;

namespace yas::db {
static db::object_ptr const _empty_object = nullptr;
static std::string const _empty_string;
static std::vector<std::size_t> const _empty_indices;
static db::value const _empty_value = nullptr;
}  // namespace yas::db

object_event db::object_event::make_fetched(db::object_ptr const &object) {
    return object_event{
        object_event_type::fetched, object, db::null_id(), _empty_string, _empty_string, _empty_indices, _empty_value};
}

object_event db::object_event::make_loaded(db::object_ptr const &object) {
    return object_event{
        object_event_type::loaded, object, db::null_id(), _empty_string, _empty_string, _empty_indices, _empty_value};
}

object_event db::object_event::make_cleared(db::object_ptr const &object) {
    return object_event{
        object_event_type::cleared, object, db::null_id(), _empty_string, _empty_string, _empty_indices, _empty_value};
}

object_event db::object_event::make_attribute_updated(db::object_ptr const &object, std::string const &name,
                                                      db::value const &value) {
    return object_event{
        object_event_type::attribute_updated, object, db::null_id(), name, _empty_string, _empty_indices, value};
}

object_event db::object_event::make_relation_inserted(db::object_ptr const &object, std::string const &name,
                                                      std::vector<std::size_t> &&indices) {
    return object_event{
        object_event_type::relation_inserted, object, db::null_id(), name, _empty_string, indices, _empty_value};
}

object_event db::object_event::make_relation_removed(db::object_ptr const &object, std::string const &name,
                                                     std::vector<std::size_t> &&indices) {
    return object_event{
        object_event_type::relation_removed, object, db::null_id(), name, _empty_string, indices, _empty_value};
}

object_event db::object_event::make_relation_replaced(db::object_ptr const &object, std::string const &name) {
    return object_event{
        object_event_type::relation_replaced, object, db::null_id(), name, _empty_string, _empty_indices, _empty_value};
}

object_event db::object_event::make_erased(std::string const &entity_name, db::object_id const &object_id) {
    return object_event{
        object_event_type::erased, _empty_object, object_id, _empty_string, entity_name, _empty_indices, _empty_value};
}

db::object_event::object_event(object_event_type const type, object_ptr const &object, db::object_id const &object_id,
                               std::string const &name, std::string const &entity_name,
                               std::vector<std::size_t> const &indices, db::value const &value)
    : type(type),
      object(object),
      _object_id(object_id),
      _name(name),
      _entity_name(entity_name),
      _indices(indices),
      _value(value) {
}

bool object_event::is_changed() const {
    switch (this->type) {
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
    return this->type == object_event_type::erased;
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
