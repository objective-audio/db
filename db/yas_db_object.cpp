//
//  yas_db_object.cpp
//

#include "yas_db_object.h"
#include "yas_chaining.h"
#include "yas_db_attribute.h"
#include "yas_db_entity.h"
#include "yas_db_manager.h"
#include "yas_db_manager_utils.h"
#include "yas_db_model.h"
#include "yas_db_object_id.h"
#include "yas_db_relation.h"
#include "yas_db_value.h"
#include "yas_fast_each.h"
#include "yas_stl_utils.h"

using namespace yas;

#pragma mark - db::object_event

namespace yas::db {
object_event make_object_fetched_event(db::object object) {
    return object_event{object_fetched_event{.object = std::move(object)}};
}

object_event make_object_loaded_event(db::object object) {
    return object_event{object_loaded_event{.object = std::move(object)}};
}

object_event make_object_unloaded_event(db::object object) {
    return object_event{object_unloaded_event{.object = std::move(object)}};
}

object_event make_object_attribute_updated_event(std::string const &name, db::value const &value) {
    return object_event{object_attribute_updated_event{.name = name, .value = value}};
}

object_event make_object_relation_inserted_event(std::string const &name, std::vector<std::size_t> &&indices) {
    return object_event{object_relation_inserted_event{.name = name, .indices = std::move(indices)}};
}

object_event make_object_relation_removed_event(std::string const &name, std::vector<std::size_t> &&indices) {
    return object_event{object_relation_removed_event{.name = name, .indices = std::move(indices)}};
}

object_event make_object_relation_replaced_event(std::string const &name) {
    return object_event{object_relation_replaced_event{.name = name}};
}

object_event make_object_erased_event(std::string const &entity_name, db::object_id const &object_id) {
    return object_event{object_erased_event{.entity_name = entity_name, .object_id = object_id}};
}
}  // namespace yas::db

struct db::object_event::impl_base : base::impl {
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
    : base(std::make_shared<impl<object_fetched_event>>(std::move(event))) {
}

db::object_event::object_event(object_loaded_event &&event)
    : base(std::make_shared<impl<object_loaded_event>>(std::move(event))) {
}

db::object_event::object_event(object_unloaded_event &&event)
    : base(std::make_shared<impl<object_unloaded_event>>(std::move(event))) {
}

db::object_event::object_event(object_attribute_updated_event &&event)
    : base(std::make_shared<impl<object_attribute_updated_event>>(std::move(event))) {
}

db::object_event::object_event(object_relation_inserted_event &&event)
    : base(std::make_shared<impl<object_relation_inserted_event>>(std::move(event))) {
}

db::object_event::object_event(object_relation_removed_event &&event)
    : base(std::make_shared<impl<object_relation_removed_event>>(std::move(event))) {
}

db::object_event::object_event(object_relation_replaced_event &&event)
    : base(std::make_shared<impl<object_relation_replaced_event>>(std::move(event))) {
}

db::object_event::object_event(object_erased_event &&event)
    : base(std::make_shared<impl<object_erased_event>>(std::move(event))) {
}

db::object_event::object_event(std::nullptr_t) : base(nullptr) {
}

db::object_event_type db::object_event::type() const {
    return this->template impl_ptr<impl_base>()->type();
}

template <typename Event>
Event const &db::object_event::get() const {
    if (auto ip = std::dynamic_pointer_cast<impl<Event>>(impl_ptr())) {
        return ip->event;
    }

    throw std::runtime_error("get event failed.");
}

template db::object_fetched_event const &db::object_event::get<db::object_fetched_event>() const;
template db::object_loaded_event const &db::object_event::get<db::object_loaded_event>() const;
template db::object_unloaded_event const &db::object_event::get<db::object_unloaded_event>() const;
template db::object_attribute_updated_event const &db::object_event::get<db::object_attribute_updated_event>() const;
template db::object_relation_inserted_event const &db::object_event::get<db::object_relation_inserted_event>() const;
template db::object_relation_removed_event const &db::object_event::get<db::object_relation_removed_event>() const;
template db::object_relation_replaced_event const &db::object_event::get<db::object_relation_replaced_event>() const;
template db::object_erased_event const &db::object_event::get<db::object_erased_event>() const;

#pragma mark - db::const_object::impl

struct db::const_object::impl : base::impl {
    db::entity _entity;
    db::value_map_t _attributes;
    db::id_vector_map_t _relations;
    db::object_id _identifier;

    // const_objectとして作る場合
    impl(db::entity const &entity, db::object_data const &obj_data = {.object_id = db::null_id()})
        : _entity(entity), _identifier(nullptr) {
        this->load_data(obj_data);
    }

    // mutableなobjectとして作る場合
    impl(db::entity const &entity, db::object_id &&identifier) : _entity(entity), _identifier(std::move(identifier)) {
    }

    void clear() {
        this->_attributes.clear();
        this->_relations.clear();
    }

    bool is_equal_to_action(std::string const &action) {
        if (this->_attributes.count(action_field) > 0) {
            return this->_attributes.at(action_field).get<db::text>() == action;
        }

        return false;
    }

    void load_data(db::object_data const &obj_data) {
        this->clear();

        this->update_identifier(obj_data);

        for (auto const &pair : this->_entity.all_attributes) {
            std::string const &attr_name = pair.first;
            if (obj_data.attributes.count(attr_name) > 0) {
                this->validate_attribute_name(attr_name);

                this->_attributes.emplace(attr_name, obj_data.attributes.at(attr_name));
            }
        }

        for (auto const &pair : this->_entity.relations) {
            std::string const &rel_name = pair.first;
            if (obj_data.relations.count(rel_name) > 0) {
                this->validate_relation_name(rel_name);

                this->_relations.emplace(rel_name, obj_data.relations.at(rel_name));
            }
        }
    }

    db::value const &attribute_value(std::string const &attr_name) {
        this->validate_attribute_name(attr_name);

        if (attr_name == db::object_id_field) {
            throw std::invalid_argument("can not get 'obj_id' from attribute_value. use 'object_id()'");
        }

        if (this->_attributes.count(attr_name) > 0) {
            return this->_attributes.at(attr_name);
        }

        return db::null_value();
    }

    db::id_vector_map_t const &all_relation_ids() const {
        return this->_relations;
    }

    db::id_vector_t relation_ids(std::string const &rel_name) {
        this->validate_relation_name(rel_name);

        if (this->_relations.count(rel_name) > 0) {
            return this->_relations.at(rel_name);
        }
        return {};
    }

    db::object_id const &relation_id(std::string const &rel_name, std::size_t const idx) {
        this->validate_relation_name(rel_name);

        if (this->_relations.count(rel_name) > 0) {
            auto const &ids = this->_relations.at(rel_name);
            if (idx < ids.size()) {
                return ids.at(idx);
            }
        }
        return db::null_id();
    }

    std::size_t relation_size(std::string const &rel_name) {
        this->validate_relation_name(rel_name);

        if (this->_relations.count(rel_name) > 0) {
            return this->_relations.at(rel_name).size();
        }
        return 0;
    }

    void validate_attribute_name(std::string const &attr_name) {
        if (!this->_entity.all_attributes.count(attr_name)) {
            throw "attribute name (" + attr_name + ") not found in " + this->_entity.name + ".";
        }
    }

    void validate_relation_name(std::string const &rel_name) {
        if (!this->_entity.relations.count(rel_name)) {
            throw "relation name (" + rel_name + ") not found in " + this->_entity.name + ".";
        }
    }

    void validate_relation_id(db::object_id const &rel_id) {
        if (!rel_id) {
            throw std::runtime_error("object_id not found for relation.");
        }

        if (rel_id.is_stable() && rel_id.stable() <= 0) {
            throw std::runtime_error("invalid object_id stable for relation.");
        }
    }

    void validate_relation_ids(db::id_vector_t const &rel_ids) {
        for (db::object_id const &rel_id : rel_ids) {
            this->validate_relation_id(rel_id);
        }
    }

    void update_identifier(db::value stable) {
        if (this->_identifier) {
            this->_identifier.set_stable(std::move(stable));
        } else {
            this->_identifier = db::make_stable_id(std::move(stable));
        }
    }

    void update_identifier(db::object_data const &obj_data) {
        if (obj_data.object_id) {
            this->_validate_temporary_id(obj_data.object_id);
            this->update_identifier(obj_data.object_id.stable_value());
        } else {
            throw std::invalid_argument("object_id not found in object_data.");
        }
    }

   private:
    void _validate_temporary_id(db::object_id const &other_object_id) {
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
};

#pragma mark - db::const_object

db::const_object::const_object(db::entity const &entity, db::object_data const &obj_data)
    : base(std::make_unique<impl>(entity, obj_data)) {
}

db::const_object::const_object(std::nullptr_t) : base(nullptr) {
}

db::const_object::const_object(std::shared_ptr<impl> const &impl) : base(impl) {
}

db::const_object::const_object(std::shared_ptr<impl> &&impl) : base(std::move(impl)) {
}

db::entity const &db::const_object::entity() const {
    return impl_ptr<impl>()->_entity;
}

std::string const &db::const_object::entity_name() const {
    return impl_ptr<impl>()->_entity.name;
}

db::value const &db::const_object::attribute_value(std::string const &attr_name) const {
    return impl_ptr<impl>()->attribute_value(attr_name);
}

db::id_vector_map_t const &db::const_object::all_relation_ids() const {
    return impl_ptr<impl>()->all_relation_ids();
}

db::id_vector_t db::const_object::relation_ids(std::string const &rel_name) const {
    return impl_ptr<impl>()->relation_ids(rel_name);
}

db::object_id const &db::const_object::relation_id(std::string const &rel_name, std::size_t const idx) const {
    return impl_ptr<impl>()->relation_id(rel_name, idx);
}

std::size_t db::const_object::relation_size(std::string const &rel_name) const {
    return impl_ptr<impl>()->relation_size(rel_name);
}

db::object_id const &db::const_object::object_id() const {
    return impl_ptr<impl>()->_identifier;
}

db::value const &db::const_object::save_id() const {
    return this->attribute_value(save_id_field);
}

db::value const &db::const_object::action() const {
    return this->attribute_value(action_field);
}

bool db::const_object::is_inserted() const {
    return impl_ptr<impl>()->is_equal_to_action(db::insert_action);
}

bool db::const_object::is_updated() const {
    return impl_ptr<impl>()->is_equal_to_action(db::update_action);
}

bool db::const_object::is_removed() const {
    return impl_ptr<impl>()->is_equal_to_action(db::remove_action);
}

#pragma mark - db::object::impl

struct db::object::impl : const_object::impl, manageable_object::impl {
    enum db::object_status _status = db::object_status::invalid;
    db::manager _manager;
    chaining::notifier<chaining_pair_t> _notifier;
    chaining::fetcher<object_event> _fetcher = nullptr;

    impl(db::manager const &manager, db::entity const &entity, bool const is_temporary)
        : const_object::impl(entity, db::make_temporary_id()), _manager(manager) {
    }

    ~impl() {
        if (this->_manager) {
            if (db::object_observable &observable = this->_manager.object_observable()) {
                observable.object_did_erase(_entity.name, this->_identifier);
            }
        }

        this->_fetcher.broadcast(make_object_erased_event(this->_entity.name, this->_identifier));
    }

    void prepare(db::object &object) {
        this->_fetcher = chaining::fetcher<object_event>{[weak_object = to_weak(object)]() { return nullopt; }};
    }

    void clear() {
        const_object::impl::clear();
        this->_status = db::object_status::invalid;
    }

    // object_dataのデータを読み込んで上書きする
    // force == falseなら、データベースへの保存処理を始めた後でもオブジェクトに変更があったら上書きしない
    // force == trueなら、必ず上書きする
    void load_data(db::object_data const &obj_data, bool const force) override {
        if (this->_status != db::object_status::changed || force) {
            this->clear();

            this->update_identifier(obj_data);

            for (auto const &pair : this->_entity.all_attributes) {
                std::string const &attr_name = pair.first;
                if (obj_data.attributes.count(attr_name) > 0) {
                    this->set_attribute_value(attr_name, obj_data.attributes.at(attr_name), true);
                }
            }

            for (auto const &pair : this->_entity.relations) {
                std::string const &rel_name = pair.first;
                if (obj_data.relations.count(rel_name) > 0) {
                    this->set_relation_ids(rel_name, obj_data.relations.at(rel_name), true);
                }
            }

            if (obj_data.attributes.count(db::save_id_field) > 0) {
                this->_status = db::object_status::saved;
            }

            notify_did_change(method::loading_changed, "", false);
            this->_fetcher.broadcast(make_object_loaded_event(cast<db::object>()));
        }
    }

    void load_save_id(db::value const &save_id) override {
        this->set_attribute_value(db::save_id_field, save_id, true);
    }

    void load_insertion_data() override {
        this->_status = db::object_status::created;
        this->set_attribute_value(db::action_field, db::insert_action_value(), true);

        for (auto const &pair : this->_entity.all_attributes) {
            db::attribute const &attr = pair.second;
            if (attr.default_value) {
                this->set_attribute_value(attr.name, attr.default_value, true);
            }
        }
    }

    void clear_data() override {
        this->clear();

        this->notify_did_change(db::object::method::loading_changed, "", false);
        this->_fetcher.broadcast(make_object_unloaded_event(cast<db::object>()));
    }

    void set_attribute_value(std::string const &attr_name, db::value const &value, bool const loading = false) {
        if (attr_name == db::object_id_field) {
            return;
        }

        this->validate_attribute_name(attr_name);

        if (this->_attributes.count(attr_name) && this->_attributes.at(attr_name) == value) {
            return;
        }

        replace(this->_attributes, attr_name, value);

        if (!loading) {
            if (attr_name != db::action_field) {
                this->set_update_action();
            }

            if (this->_status != db::object_status::created) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::attribute_changed, attr_name, true);
            this->_fetcher.broadcast(make_object_attribute_updated_event(attr_name, value));
        }
    }

    void set_relation_ids(std::string const &rel_name, db::id_vector_t const &relation_ids,
                          bool const loading = false) {
        if (this->_relations.count(rel_name) && this->_relations.at(rel_name) == relation_ids) {
            return;
        }

        this->validate_relation_name(rel_name);
        this->validate_relation_ids(relation_ids);

        replace(this->_relations, rel_name, relation_ids);

        if (!loading) {
            this->set_update_action();

            if (this->_status != db::object_status::created) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name, {change_reason::replaced, {}},
                                    true);
            this->_fetcher.broadcast(make_object_relation_replaced_event(rel_name));
        }
    }

    void add_relation_id(std::string const &rel_name, db::object_id const &rel_id) {
        if (this->_relations.count(rel_name) > 0) {
            this->insert_relation_id(rel_name, rel_id, this->_relations.at(rel_name).size());
        } else {
            this->insert_relation_id(rel_name, rel_id, 0);
        }
    }

    void insert_relation_id(std::string const &rel_name, db::object_id const &relation_id, std::size_t const idx) {
        this->validate_relation_name(rel_name);
        this->validate_relation_id(relation_id);

        if (this->_relations.count(rel_name) == 0) {
            this->_relations.emplace(rel_name, db::id_vector_t{});
        }

        auto &vector = _relations.at(rel_name);
        vector.insert(vector.begin() + idx, relation_id);

        this->set_update_action();

        if (this->_status != db::object_status::created) {
            this->_status = db::object_status::changed;
        }

        this->notify_did_change(db::object::method::relation_changed, rel_name, {change_reason::inserted, {idx}}, true);
        this->_fetcher.broadcast(make_object_relation_inserted_event(rel_name, {idx}));
    }

    void remove_relation_id(std::string const &rel_name, db::object_id const &relation_id) {
        this->validate_relation_name(rel_name);
        this->validate_relation_id(relation_id);

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

            this->set_update_action();

            if (this->_status != db::object_status::created) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name, {change_reason::removed, indices},
                                    true);
            this->_fetcher.broadcast(make_object_relation_removed_event(rel_name, std::move(indices)));
        }
    }

    void remove_relation_at(std::string const &rel_name, std::size_t const idx) {
        this->validate_relation_name(rel_name);

        if (this->_relations.count(rel_name) > 0) {
            auto &ids = this->_relations.at(rel_name);
            if (idx < ids.size()) {
                ids.erase(ids.begin() + idx);
            }

            this->set_update_action();

            if (this->_status != db::object_status::created) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name, {change_reason::removed, {idx}},
                                    true);
            this->_fetcher.broadcast(make_object_relation_removed_event(rel_name, {idx}));
        }
    }

    void remove_all_relations(std::string const &rel_name) {
        this->validate_relation_name(rel_name);

        if (this->_entity.relations.count(rel_name) == 0) {
            throw "relation name (" + rel_name + ") not found";
        }

        if (this->_relations.count(rel_name) > 0) {
            std::size_t const rel_size = this->_relations.at(rel_name).size();

            this->_relations.erase(rel_name);

            this->set_update_action();

            if (this->_status != db::object_status::created) {
                this->_status = db::object_status::changed;
            }

            std::vector<std::size_t> indices;
            indices.reserve(rel_size);
            auto each = make_fast_each(rel_size);
            while (yas_each_next(each)) {
                indices.push_back(yas_each_index(each));
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name, {change_reason::removed, indices},
                                    true);
            this->_fetcher.broadcast(make_object_relation_removed_event(rel_name, std::move(indices)));
        }
    }

    void remove() {
        if (this->is_equal_to_action(db::remove_action)) {
            return;
        }

        erase_if(this->_attributes, [](auto const &pair) {
            std::string const &column_name = pair.first;
            if (column_name == db::pk_id_field || column_name == db::object_id_field ||
                column_name == db::action_field) {
                return false;
            }
            return true;
        });

        this->_relations.clear();

        this->set_attribute_value(db::action_field, db::remove_action_value());
    }

    db::object_data save_data(db::object_id_pool_t &pool) {
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

    void set_update_action() {
        if (this->_status != db::object_status::created && !this->is_equal_to_action(db::remove_action) &&
            !this->is_equal_to_action(db::update_action)) {
            this->set_attribute_value(db::action_field, db::update_action_value(), true);
        }
    }

    void set_status(db::object_status const &stat) override {
        this->_status = stat;
    }

    void notify_did_change(db::object::method const &key, std::string const &name, bool const send_to_manager) {
        this->_notifier.notify(std::make_pair(key, db::object::change_info{cast<db::object>(), name}));

        if (send_to_manager && this->_manager) {
            if (db::object_observable &observable = this->_manager.object_observable()) {
                observable.object_did_change(cast<db::object>());
            }
        }
    }

    void notify_did_change(db::object::method const &key, std::string const &name,
                           db::object::relation_change_info &&rel_change_info, bool const send_to_manager) {
        this->_notifier.notify(
            std::make_pair(key, db::object::change_info{cast<db::object>(), name, std::move(rel_change_info)}));

        if (send_to_manager && this->_manager) {
            if (db::object_observable &observable = this->_manager.object_observable()) {
                observable.object_did_change(cast<db::object>());
            }
        }
    }
};

#pragma mark - db::object::change_info

db::object::change_info::change_info(db::object const &object, std::string const &name) : object(object), name(name) {
}

db::object::change_info::change_info(db::object const &object, std::string const &name,
                                     db::object::relation_change_info &&rel_change_info)
    : object(object), name(name), _rel_change_info(std::move(rel_change_info)) {
}

db::object::relation_change_info const &db::object::change_info::relation_change_info() const {
    return *_rel_change_info;
}

#pragma mark - db::object

db::object::object(db::manager const &manager, db::entity const &entity)
    : const_object(std::make_unique<impl>(manager, entity, true)) {
    impl_ptr<impl>()->prepare(*this);
}

db::object::object(std::nullptr_t) : const_object(nullptr) {
}

chaining::chain_syncable_t<db::object_event> db::object::chain() const {
    return impl_ptr<impl>()->_fetcher.chain();
}

void db::object::set_attribute_value(std::string const &attr_name, db::value const &value) {
    impl_ptr<impl>()->set_attribute_value(attr_name, value);
}

db::object_vector_t db::object::relation_objects(std::string const &rel_name) const {
    auto const &rel_ids = impl_ptr<impl>()->relation_ids(rel_name);
    std::string const &tgt_entity_name = this->entity().relations.at(rel_name).target;
    return to_vector<db::object>(rel_ids, [manager = manager(), &tgt_entity_name](db::object_id const &rel_id) {
        return manager.cached_or_created_object(tgt_entity_name, rel_id);
    });
}

db::object db::object::relation_object_at(std::string const &rel_name, std::size_t const idx) const {
    std::string const &tgt_entity_name = this->entity().relations.at(rel_name).target;
    return this->manager().cached_or_created_object(tgt_entity_name, relation_id(rel_name, idx));
}

void db::object::set_relation_ids(std::string const &rel_name, db::id_vector_t const &relation_ids) {
    impl_ptr<impl>()->set_relation_ids(rel_name, relation_ids);
}

void db::object::add_relation_id(std::string const &rel_name, db::object_id const &rel_id) {
    impl_ptr<impl>()->add_relation_id(rel_name, rel_id);
}

void db::object::insert_relation_id(std::string const &rel_name, db::object_id const &rel_id, std::size_t const idx) {
    impl_ptr<impl>()->insert_relation_id(rel_name, rel_id, idx);
}

void db::object::remove_relation_id(std::string const &rel_name, db::object_id const &rel_id) {
    impl_ptr<impl>()->remove_relation_id(rel_name, rel_id);
}

void db::object::set_relation_objects(std::string const &rel_name, db::object_vector_t const &rel_objects) {
    impl_ptr<impl>()->set_relation_ids(
        rel_name, to_vector<db::object_id>(
                      rel_objects, [entity_name = entity_name()](db::object const &obj) { return obj.object_id(); }));
}

void db::object::add_relation_object(std::string const &rel_name, db::object const &rel_object) {
    impl_ptr<impl>()->add_relation_id(rel_name, rel_object.object_id());
}

void db::object::insert_relation_object(std::string const &rel_name, db::object const &rel_object,
                                        std::size_t const idx) {
    impl_ptr<impl>()->insert_relation_id(rel_name, rel_object.object_id(), idx);
}

void db::object::remove_relation_object(std::string const &rel_name, object const &rel_object) {
    impl_ptr<impl>()->remove_relation_id(rel_name, rel_object.object_id());
}

void db::object::remove_relation_at(std::string const &rel_name, std::size_t const idx) {
    impl_ptr<impl>()->remove_relation_at(rel_name, idx);
}

void db::object::remove_all_relations(std::string const &rel_name) {
    impl_ptr<impl>()->remove_all_relations(rel_name);
}

db::manager const &db::object::manager() const {
    return impl_ptr<impl>()->_manager;
}

enum db::object_status db::object::status() const {
    return impl_ptr<impl>()->_status;
}

void db::object::remove() {
    impl_ptr<impl>()->remove();
}

bool db::object::is_temporary() const {
    return this->save_id().get<db::integer>() <= 0;
}

db::object_data db::object::save_data(db::object_id_pool_t &pool) const {
    return impl_ptr<impl>()->save_data(pool);
}

db::manageable_object &db::object::manageable() {
    if (!_manageable) {
        _manageable = manageable_object{impl_ptr<manageable_object::impl>()};
    }
    return _manageable;
}

#pragma mark -

db::const_object const &db::null_const_object() {
    static db::const_object const _null_object{nullptr};
    return _null_object;
}

db::object const &db::null_object() {
    static db::object const _null_object{nullptr};
    return _null_object;
}

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
