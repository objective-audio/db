//
//  yas_db_object.cpp
//

#include "yas_db_object.h"

#include <chaining/yas_chaining_umbrella.h>
#include <cpp_utils/yas_fast_each.h>
#include <cpp_utils/yas_stl_utils.h>

#include "yas_db_attribute.h"
#include "yas_db_manager_utils.h"
#include "yas_db_model.h"
#include "yas_db_object_id.h"
#include "yas_db_relation.h"
#include "yas_db_value.h"

using namespace yas;

#pragma mark - db::object_event

namespace yas::db {
object_event make_object_fetched_event(db::object_ptr const &object) {
    return object_event{object_fetched_event{.object = object}};
}

object_event make_object_loaded_event(db::object_ptr const &object) {
    return object_event{object_loaded_event{.object = object}};
}

object_event make_object_cleared_event(db::object_ptr const &object) {
    return object_event{object_cleared_event{.object = object}};
}

object_event make_object_attribute_updated_event(db::object_ptr const &object, std::string const &name,
                                                 db::value const &value) {
    return object_event{object_attribute_updated_event{.object = object, .name = name, .value = value}};
}

object_event make_object_relation_inserted_event(db::object_ptr const &object, std::string const &name,
                                                 std::vector<std::size_t> &&indices) {
    return object_event{object_relation_inserted_event{.object = object, .name = name, .indices = std::move(indices)}};
}

object_event make_object_relation_removed_event(db::object_ptr const &object, std::string const &name,
                                                std::vector<std::size_t> &&indices) {
    return object_event{object_relation_removed_event{.object = object, .name = name, .indices = std::move(indices)}};
}

object_event make_object_relation_replaced_event(db::object_ptr const &object, std::string const &name) {
    return object_event{object_relation_replaced_event{.object = object, .name = name}};
}

object_event make_object_erased_event(std::string const &entity_name, db::object_id const &object_id) {
    return object_event{object_erased_event{.entity_name = entity_name, .object_id = object_id}};
}
}  // namespace yas::db

struct db::object_event::impl_base {
    virtual object_event_type type() {
        throw std::runtime_error("type() must be overridden");
    }
};

template <typename Event>
struct db::object_event::impl : db::object_event::impl_base {
    Event const event;

    impl(Event &&event) : event(std::move(event)) {
    }

    object_event_type type() override {
        return Event::type;
    }
};

db::object_event::object_event(object_fetched_event &&event)
    : _impl(std::make_shared<impl<object_fetched_event>>(std::move(event))) {
}

db::object_event::object_event(object_loaded_event &&event)
    : _impl(std::make_shared<impl<object_loaded_event>>(std::move(event))) {
}

db::object_event::object_event(object_cleared_event &&event)
    : _impl(std::make_shared<impl<object_cleared_event>>(std::move(event))) {
}

db::object_event::object_event(object_attribute_updated_event &&event)
    : _impl(std::make_shared<impl<object_attribute_updated_event>>(std::move(event))) {
}

db::object_event::object_event(object_relation_inserted_event &&event)
    : _impl(std::make_shared<impl<object_relation_inserted_event>>(std::move(event))) {
}

db::object_event::object_event(object_relation_removed_event &&event)
    : _impl(std::make_shared<impl<object_relation_removed_event>>(std::move(event))) {
}

db::object_event::object_event(object_relation_replaced_event &&event)
    : _impl(std::make_shared<impl<object_relation_replaced_event>>(std::move(event))) {
}

db::object_event::object_event(object_erased_event &&event)
    : _impl(std::make_shared<impl<object_erased_event>>(std::move(event))) {
}

db::object_event::object_event(std::nullptr_t) : _impl(nullptr) {
}

db::object_event_type db::object_event::type() const {
    return this->_impl->type();
}

template <typename Event>
Event const &db::object_event::get() const {
    if (auto ip = std::dynamic_pointer_cast<impl<Event>>(this->_impl)) {
        return ip->event;
    }

    throw std::runtime_error("get event failed.");
}

bool db::object_event::is_changed() const {
    switch (this->type()) {
        case db::object_event_type::attribute_updated:
        case db::object_event_type::relation_inserted:
        case db::object_event_type::relation_removed:
        case db::object_event_type::relation_replaced:
            return true;
        default:
            return false;
    }
}

bool db::object_event::is_erased() const {
    return this->type() == db::object_event_type::erased;
}

db::object_ptr const &db::object_event::object() const {
    switch (this->type()) {
        case db::object_event_type::fetched:
            return this->get<db::object_fetched_event>().object;
        case db::object_event_type::loaded:
            return this->get<db::object_loaded_event>().object;
        case db::object_event_type::cleared:
            return this->get<db::object_cleared_event>().object;
        case db::object_event_type::attribute_updated:
            return this->get<db::object_attribute_updated_event>().object;
        case db::object_event_type::relation_inserted:
            return this->get<db::object_relation_inserted_event>().object;
        case db::object_event_type::relation_removed:
            return this->get<db::object_relation_removed_event>().object;
        case db::object_event_type::relation_replaced:
            return this->get<db::object_relation_replaced_event>().object;
        default:
            throw std::runtime_error("object not found.");
    }
}

template db::object_fetched_event const &db::object_event::get<db::object_fetched_event>() const;
template db::object_loaded_event const &db::object_event::get<db::object_loaded_event>() const;
template db::object_cleared_event const &db::object_event::get<db::object_cleared_event>() const;
template db::object_attribute_updated_event const &db::object_event::get<db::object_attribute_updated_event>() const;
template db::object_relation_inserted_event const &db::object_event::get<db::object_relation_inserted_event>() const;
template db::object_relation_removed_event const &db::object_event::get<db::object_relation_removed_event>() const;
template db::object_relation_replaced_event const &db::object_event::get<db::object_relation_replaced_event>() const;
template db::object_erased_event const &db::object_event::get<db::object_erased_event>() const;

#pragma mark - db::const_object

db::const_object::const_object(db::entity const &entity, db::object_data const &obj_data)
    : _entity(entity), _identifier(nullptr) {
    this->_load_data(obj_data);
}

db::const_object::const_object(db::entity const &entity, db::object_id &&identifier)
    : _entity(entity), _identifier(std::move(identifier)) {
}

db::entity const &db::const_object::entity() const {
    return this->_entity;
}

std::string const &db::const_object::entity_name() const {
    return this->_entity.name;
}

db::value const &db::const_object::attribute_value(std::string const &attr_name) const {
    this->_validate_attribute_name(attr_name);

    if (attr_name == db::object_id_field) {
        throw std::invalid_argument("can not get 'obj_id' from attribute_value. use 'object_id()'");
    }

    if (this->_attributes.count(attr_name) > 0) {
        return this->_attributes.at(attr_name);
    }

    return db::null_value();
}

db::id_vector_map_t const &db::const_object::all_relation_ids() const {
    return this->_relations;
}

db::id_vector_t db::const_object::relation_ids(std::string const &rel_name) const {
    this->_validate_relation_name(rel_name);

    if (this->_relations.count(rel_name) > 0) {
        return this->_relations.at(rel_name);
    }
    return {};
}

db::object_id const &db::const_object::relation_id(std::string const &rel_name, std::size_t const idx) const {
    this->_validate_relation_name(rel_name);

    if (this->_relations.count(rel_name) > 0) {
        auto const &ids = this->_relations.at(rel_name);
        if (idx < ids.size()) {
            return ids.at(idx);
        }
    }
    return db::null_id();
}

std::size_t db::const_object::relation_size(std::string const &rel_name) const {
    this->_validate_relation_name(rel_name);

    if (this->_relations.count(rel_name) > 0) {
        return this->_relations.at(rel_name).size();
    }
    return 0;
}

db::object_id const &db::const_object::object_id() const {
    return this->_identifier;
}

db::value const &db::const_object::save_id() const {
    return this->attribute_value(save_id_field);
}

db::value const &db::const_object::action() const {
    return this->attribute_value(action_field);
}

bool db::const_object::is_inserted() const {
    return this->_is_equal_to_action(db::insert_action);
}

bool db::const_object::is_updated() const {
    return this->_is_equal_to_action(db::update_action);
}

bool db::const_object::is_removed() const {
    return this->_is_equal_to_action(db::remove_action);
}

void db::const_object::_load_data(db::object_data const &obj_data) {
    this->_clear();

    this->_update_identifier(obj_data);

    for (auto const &pair : this->_entity.all_attributes) {
        std::string const &attr_name = pair.first;
        if (obj_data.attributes.count(attr_name) > 0) {
            this->_validate_attribute_name(attr_name);

            this->_attributes.emplace(attr_name, obj_data.attributes.at(attr_name));
        }
    }

    for (auto const &pair : this->_entity.relations) {
        std::string const &rel_name = pair.first;
        if (obj_data.relations.count(rel_name) > 0) {
            this->_validate_relation_name(rel_name);

            this->_relations.emplace(rel_name, obj_data.relations.at(rel_name));
        }
    }
}

void db::const_object::_clear() {
    this->_attributes.clear();
    this->_relations.clear();
}

bool db::const_object::_is_equal_to_action(std::string const &action) const {
    if (this->_attributes.count(action_field) > 0) {
        return this->_attributes.at(action_field).get<db::text>() == action;
    }

    return false;
}

void db::const_object::_update_identifier(db::value stable) {
    if (this->_identifier) {
        this->_identifier.set_stable(std::move(stable));
    } else {
        this->_identifier = db::make_stable_id(std::move(stable));
    }
}

void db::const_object::_update_identifier(db::object_data const &obj_data) {
    if (obj_data.object_id) {
        this->_validate_temporary_id(obj_data.object_id);
        this->_update_identifier(obj_data.object_id.stable_value());
    } else {
        throw std::invalid_argument("object_id not found in object_data.");
    }
}

void db::const_object::_validate_attribute_name(std::string const &attr_name) const {
    if (!this->_entity.all_attributes.count(attr_name)) {
        throw std::runtime_error("attribute name (" + attr_name + ") not found in " + this->_entity.name + ".");
    }
}

void db::const_object::_validate_relation_name(std::string const &rel_name) const {
    if (!this->_entity.relations.count(rel_name)) {
        throw std::runtime_error("relation name (" + rel_name + ") not found in " + this->_entity.name + ".");
    }
}

void db::const_object::_validate_relation_id(db::object_id const &rel_id) const {
    if (!rel_id) {
        throw std::runtime_error("object_id not found for relation.");
    }

    if (rel_id.is_stable() && rel_id.stable() <= 0) {
        throw std::runtime_error("invalid object_id stable for relation.");
    }
}

void db::const_object::_validate_relation_ids(db::id_vector_t const &rel_ids) const {
    for (db::object_id const &rel_id : rel_ids) {
        this->_validate_relation_id(rel_id);
    }
}

void db::const_object::_validate_temporary_id(db::object_id const &other_object_id) const {
    if (!other_object_id) {
        return;
    }

    if (!other_object_id.temporary_value()) {
        return;
    }

    if (!this->_identifier.temporary_value()) {
        return;
    }

    if (other_object_id.temporary() != this->_identifier.temporary()) {
        throw std::invalid_argument("not equal temporary values.");
    }
}

db::const_object_ptr db::const_object::make_shared(db::entity const &entity, db::object_data const &obj_data) {
    return const_object_ptr(new const_object{entity, obj_data});
}

#pragma mark - db::object

db::object::object(db::entity const &entity) : const_object(entity, db::make_temporary_id()) {
}

db::object::~object() {
    this->_sender->broadcast(make_object_erased_event(this->_entity.name, this->_identifier));
}

chaining::chain_sync_t<db::object_event> db::object::chain() const {
    return this->_fetcher->chain();
}

void db::object::set_attribute_value(std::string const &attr_name, db::value const &value) {
    this->_set_attribute_value(attr_name, value, false);
}

void db::object::set_relation_ids(std::string const &rel_name, db::id_vector_t const &relation_ids) {
    this->_set_relation_ids(rel_name, relation_ids);
}

void db::object::add_relation_id(std::string const &rel_name, db::object_id const &rel_id) {
    if (this->_relations.count(rel_name) > 0) {
        this->insert_relation_id(rel_name, rel_id, this->_relations.at(rel_name).size());
    } else {
        this->insert_relation_id(rel_name, rel_id, 0);
    }
}

void db::object::insert_relation_id(std::string const &rel_name, db::object_id const &relation_id,
                                    std::size_t const idx) {
    this->_validate_relation_name(rel_name);
    this->_validate_relation_id(relation_id);

    if (this->_relations.count(rel_name) == 0) {
        this->_relations.emplace(rel_name, db::id_vector_t{});
    }

    auto &vector = this->_relations.at(rel_name);
    vector.insert(vector.begin() + idx, relation_id);

    this->_set_update_action();

    if (this->_status != db::object_status::created) {
        this->_status = db::object_status::changed;
    }

    this->_sender->broadcast(make_object_relation_inserted_event(this->_weak_object.lock(), rel_name, {idx}));
}

void db::object::remove_relation_id(std::string const &rel_name, db::object_id const &relation_id) {
    this->_validate_relation_name(rel_name);
    this->_validate_relation_id(relation_id);

    if (this->_relations.count(rel_name) > 0) {
        std::size_t idx = 0;
        std::vector<std::size_t> indices;

        erase_if(this->_relations.at(rel_name), [relation_id, &idx, &indices](db::object_id const &object_id) {
            bool const result = object_id == relation_id;
            if (result) {
                indices.push_back(idx);
            }
            ++idx;
            return result;
        });

        this->_set_update_action();

        if (this->_status != db::object_status::created) {
            this->_status = db::object_status::changed;
        }

        this->_sender->broadcast(
            make_object_relation_removed_event(this->_weak_object.lock(), rel_name, std::move(indices)));
    }
}

void db::object::set_relation_objects(std::string const &rel_name, db::object_vector_t const &rel_objects) {
    this->set_relation_ids(
        rel_name, to_vector<db::object_id>(rel_objects, [entity_name = entity_name()](db::object_ptr const &obj) {
            return obj->object_id();
        }));
}

void db::object::add_relation_object(std::string const &rel_name, db::object_ptr const &rel_object) {
    this->add_relation_id(rel_name, rel_object->object_id());
}

void db::object::insert_relation_object(std::string const &rel_name, db::object_ptr const &rel_object,
                                        std::size_t const idx) {
    this->insert_relation_id(rel_name, rel_object->object_id(), idx);
}

void db::object::remove_relation_object(std::string const &rel_name, db::object_ptr const &rel_object) {
    this->remove_relation_id(rel_name, rel_object->object_id());
}

void db::object::remove_relation_at(std::string const &rel_name, std::size_t const idx) {
    this->_validate_relation_name(rel_name);

    if (this->_relations.count(rel_name) > 0) {
        auto &ids = this->_relations.at(rel_name);
        if (idx < ids.size()) {
            ids.erase(ids.begin() + idx);
        }

        this->_set_update_action();

        if (this->_status != db::object_status::created) {
            this->_status = db::object_status::changed;
        }

        this->_sender->broadcast(make_object_relation_removed_event(this->_weak_object.lock(), rel_name, {idx}));
    }
}

void db::object::remove_all_relations(std::string const &rel_name) {
    this->_validate_relation_name(rel_name);

    if (this->_entity.relations.count(rel_name) == 0) {
        throw std::runtime_error("relation name (" + rel_name + ") not found");
    }

    if (this->_relations.count(rel_name) > 0) {
        std::size_t const rel_size = this->_relations.at(rel_name).size();

        this->_relations.erase(rel_name);

        this->_set_update_action();

        if (this->_status != db::object_status::created) {
            this->_status = db::object_status::changed;
        }

        std::vector<std::size_t> indices;
        indices.reserve(rel_size);
        auto each = make_fast_each(rel_size);
        while (yas_each_next(each)) {
            indices.push_back(yas_each_index(each));
        }

        this->_sender->broadcast(
            make_object_relation_removed_event(this->_weak_object.lock(), rel_name, std::move(indices)));
    }
}

enum db::object_status db::object::status() const {
    return this->_status;
}

void db::object::remove() {
    if (this->_is_equal_to_action(db::remove_action)) {
        return;
    }

    erase_if(this->_attributes, [](auto const &pair) {
        std::string const &column_name = pair.first;
        if (column_name == db::pk_id_field || column_name == db::object_id_field || column_name == db::action_field) {
            return false;
        }
        return true;
    });

    this->_relations.clear();

    this->_set_attribute_value(db::action_field, db::remove_action_value(), false);
}

bool db::object::is_temporary() const {
    return this->save_id().get<db::integer>() <= 0;
}

db::object_data db::object::save_data(db::object_id_pool &pool) const {
    db::value_map_t attributes;
    db::id_vector_map_t relations;

    std::string const &entity_name = this->_entity.name;
    db::object_id object_id = pool.get_or_create(entity_name, this->_identifier,
                                                 [&identifier = this->_identifier]() { return identifier.copy(); });

    if (this->_status != db::object_status::created) {
        attributes.emplace(db::object_id_field, this->_identifier.stable_value());
    }

    for (auto const &pair : this->_entity.all_attributes) {
        std::string const &attr_name = pair.first;

        if (attr_name == db::save_id_field || attr_name == db::object_id_field) {
            continue;
        }

        if (this->_attributes.count(attr_name) > 0) {
            attributes.emplace(attr_name, this->_attributes.at(attr_name));
        } else if (pair.second.not_null) {
            attributes.emplace(attr_name, pair.second.default_value);
        } else {
            attributes.emplace(attr_name, db::null_value());
        }
    }

    for (auto const &pair : this->_entity.relations) {
        std::string const &rel_name = pair.first;
        if (this->_relations.count(rel_name) > 0) {
            std::string const &rel_entity_name = pair.second.target;
            auto const &rel_ids = this->_relations.at(rel_name);
            db::id_vector_t rel_save_ids;
            rel_save_ids.reserve(rel_ids.size());
            for (db::object_id const &rel_id : rel_ids) {
                rel_save_ids.emplace_back(
                    pool.get_or_create(rel_entity_name, rel_id, [&rel_id = rel_id]() { return rel_id.copy(); }));
            }
            relations.emplace(rel_name, std::move(rel_save_ids));
        }
    }

    return db::object_data{
        .object_id = std::move(object_id), .attributes = std::move(attributes), .relations = std::move(relations)};
}

void db::object::_prepare(object_ptr const &shared) {
    this->_weak_object = shared;

    this->_fetcher = chaining::fetcher<object_event>::make_shared([weak_object = this->_weak_object]() {
        if (auto object = weak_object.lock()) {
            return std::optional<object_event>{make_object_fetched_event(object)};
        } else {
            return std::optional<object_event>{std::nullopt};
        }
    });
    this->_sender = this->_fetcher;
}

void db::object::set_status(db::object_status const &status) {
    this->_status = status;
}

void db::object::load_insertion_data() {
    this->_status = db::object_status::created;
    this->_set_attribute_value(db::action_field, db::insert_action_value(), true);

    for (auto const &pair : this->_entity.all_attributes) {
        db::attribute const &attr = pair.second;
        if (attr.default_value) {
            this->_set_attribute_value(attr.name, attr.default_value, true);
        }
    }
}

// object_dataのデータを読み込んで上書きする
// force == falseなら、データベースへの保存処理を始めた後でもオブジェクトに変更があったら上書きしない
// force == trueなら、必ず上書きする
void db::object::load_data(db::object_data const &obj_data, bool const force) {
    if (this->_status != db::object_status::changed || force) {
        this->_clear();

        this->_update_identifier(obj_data);

        for (auto const &pair : this->_entity.all_attributes) {
            std::string const &attr_name = pair.first;
            if (obj_data.attributes.count(attr_name) > 0) {
                this->_set_attribute_value(attr_name, obj_data.attributes.at(attr_name), true);
            }
        }

        for (auto const &pair : this->_entity.relations) {
            std::string const &rel_name = pair.first;
            if (obj_data.relations.count(rel_name) > 0) {
                this->_set_relation_ids(rel_name, obj_data.relations.at(rel_name), true);
            }
        }

        if (obj_data.attributes.count(db::save_id_field) > 0) {
            this->_status = db::object_status::saved;
        }

        this->_sender->broadcast(make_object_loaded_event(this->_weak_object.lock()));
    }
}

void db::object::load_save_id(db::value const &save_id) {
    this->_set_attribute_value(db::save_id_field, save_id, true);
}

void db::object::clear_data() {
    this->_clear();

    this->_sender->broadcast(make_object_cleared_event(this->_weak_object.lock()));
}

void db::object::_clear() {
    this->const_object::_clear();
    this->_status = db::object_status::invalid;
}

void db::object::_set_attribute_value(std::string const &attr_name, db::value const &value, bool const loading) {
    if (attr_name == db::object_id_field) {
        return;
    }

    this->_validate_attribute_name(attr_name);

    if (this->_attributes.count(attr_name) && this->_attributes.at(attr_name) == value) {
        return;
    }

    replace(this->_attributes, attr_name, value);

    if (!loading) {
        if (attr_name != db::action_field) {
            this->_set_update_action();
        }

        if (this->_status != db::object_status::created) {
            this->_status = db::object_status::changed;
        }

        this->_sender->broadcast(make_object_attribute_updated_event(this->_weak_object.lock(), attr_name, value));
    }
}

void db::object::_set_relation_ids(std::string const &rel_name, db::id_vector_t const &relation_ids,
                                   bool const loading) {
    if (this->_relations.count(rel_name) && this->_relations.at(rel_name) == relation_ids) {
        return;
    }

    this->_validate_relation_name(rel_name);
    this->_validate_relation_ids(relation_ids);

    replace(this->_relations, rel_name, relation_ids);

    if (!loading) {
        this->_set_update_action();

        if (this->_status != db::object_status::created) {
            this->_status = db::object_status::changed;
        }

        this->_sender->broadcast(make_object_relation_replaced_event(this->_weak_object.lock(), rel_name));
    }
}

void db::object::_set_update_action() {
    if (this->_status != db::object_status::created && !this->_is_equal_to_action(db::remove_action) &&
        !this->_is_equal_to_action(db::update_action)) {
        this->_set_attribute_value(db::action_field, db::update_action_value(), true);
    }
}

db::object_ptr db::object::make_shared(db::entity const &entity) {
    auto shared = object_ptr(new object{entity});
    shared->_prepare(shared);
    return shared;
}

#pragma mark -

db::value const &db::insert_action_value() {
    static db::value _value{db::insert_action};
    return _value;
}

db::value const &db::update_action_value() {
    static db::value _value{db::update_action};
    return _value;
}

db::value const &db::remove_action_value() {
    static db::value _value{db::remove_action};
    return _value;
}

std::string yas::to_string(db::object_status const &status) {
    switch (status) {
        case db::object_status::invalid:
            return "invalid";
        case db::object_status::created:
            return "inserted";
        case db::object_status::saved:
            return "saved";
        case db::object_status::changed:
            return "changed";
        case db::object_status::updating:
            return "updating";
    }
    return "unknown";
}
