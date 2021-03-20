//
//  yas_db_object_event.cpp
//

#include "yas_db_object_event.h"

using namespace yas;
using namespace yas::db;

object_event db::make_object_fetched_event(db::object_ptr const &object) {
    return object_event{object_fetched_event{.object = object}};
}

object_event db::make_object_loaded_event(db::object_ptr const &object) {
    return object_event{object_loaded_event{.object = object}};
}

object_event db::make_object_cleared_event(db::object_ptr const &object) {
    return object_event{object_cleared_event{.object = object}};
}

object_event db::make_object_attribute_updated_event(db::object_ptr const &object, std::string const &name,
                                                     db::value const &value) {
    return object_event{object_attribute_updated_event{.object = object, .name = name, .value = value}};
}

object_event db::make_object_relation_inserted_event(db::object_ptr const &object, std::string const &name,
                                                     std::vector<std::size_t> &&indices) {
    return object_event{object_relation_inserted_event{.object = object, .name = name, .indices = std::move(indices)}};
}

object_event db::make_object_relation_removed_event(db::object_ptr const &object, std::string const &name,
                                                    std::vector<std::size_t> &&indices) {
    return object_event{object_relation_removed_event{.object = object, .name = name, .indices = std::move(indices)}};
}

object_event db::make_object_relation_replaced_event(db::object_ptr const &object, std::string const &name) {
    return object_event{object_relation_replaced_event{.object = object, .name = name}};
}

object_event db::make_object_erased_event(std::string const &entity_name, db::object_id const &object_id) {
    return object_event{object_erased_event{.entity_name = entity_name, .object_id = object_id}};
}

struct object_event::impl_base {
    virtual object_event_type type() {
        throw std::runtime_error("type() must be overridden");
    }
};

template <typename Event>
struct object_event::impl : object_event::impl_base {
    Event const event;

    impl(Event &&event) : event(std::move(event)) {
    }

    object_event_type type() override {
        return Event::type;
    }
};

object_event::object_event(object_fetched_event &&event)
    : _impl(std::make_shared<impl<object_fetched_event>>(std::move(event))) {
}

object_event::object_event(object_loaded_event &&event)
    : _impl(std::make_shared<impl<object_loaded_event>>(std::move(event))) {
}

object_event::object_event(object_cleared_event &&event)
    : _impl(std::make_shared<impl<object_cleared_event>>(std::move(event))) {
}

object_event::object_event(object_attribute_updated_event &&event)
    : _impl(std::make_shared<impl<object_attribute_updated_event>>(std::move(event))) {
}

object_event::object_event(object_relation_inserted_event &&event)
    : _impl(std::make_shared<impl<object_relation_inserted_event>>(std::move(event))) {
}

object_event::object_event(object_relation_removed_event &&event)
    : _impl(std::make_shared<impl<object_relation_removed_event>>(std::move(event))) {
}

object_event::object_event(object_relation_replaced_event &&event)
    : _impl(std::make_shared<impl<object_relation_replaced_event>>(std::move(event))) {
}

object_event::object_event(object_erased_event &&event)
    : _impl(std::make_shared<impl<object_erased_event>>(std::move(event))) {
}

object_event::object_event(std::nullptr_t) : _impl(nullptr) {
}

object_event_type object_event::type() const {
    return this->_impl->type();
}

template <typename Event>
Event const &object_event::get() const {
    if (auto ip = std::dynamic_pointer_cast<impl<Event>>(this->_impl)) {
        return ip->event;
    }

    throw std::runtime_error("get event failed.");
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
    switch (this->type()) {
        case object_event_type::fetched:
            return this->get<db::object_fetched_event>().object;
        case object_event_type::loaded:
            return this->get<db::object_loaded_event>().object;
        case object_event_type::cleared:
            return this->get<db::object_cleared_event>().object;
        case object_event_type::attribute_updated:
            return this->get<db::object_attribute_updated_event>().object;
        case object_event_type::relation_inserted:
            return this->get<db::object_relation_inserted_event>().object;
        case object_event_type::relation_removed:
            return this->get<db::object_relation_removed_event>().object;
        case object_event_type::relation_replaced:
            return this->get<db::object_relation_replaced_event>().object;
        default:
            throw std::runtime_error("object not found.");
    }
}

template db::object_fetched_event const &object_event::get<db::object_fetched_event>() const;
template db::object_loaded_event const &object_event::get<db::object_loaded_event>() const;
template db::object_cleared_event const &object_event::get<db::object_cleared_event>() const;
template db::object_attribute_updated_event const &object_event::get<db::object_attribute_updated_event>() const;
template db::object_relation_inserted_event const &object_event::get<db::object_relation_inserted_event>() const;
template db::object_relation_removed_event const &object_event::get<db::object_relation_removed_event>() const;
template db::object_relation_replaced_event const &object_event::get<db::object_relation_replaced_event>() const;
template db::object_erased_event const &object_event::get<db::object_erased_event>() const;