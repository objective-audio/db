//
//  yas_db_object.cpp
//

#include "yas_db_attribute.h"
#include "yas_db_entity.h"
#include "yas_db_manager.h"
#include "yas_db_model.h"
#include "yas_db_object.h"
#include "yas_db_relation.h"
#include "yas_db_value.h"
#include "yas_observing.h"
#include "yas_stl_utils.h"

using namespace yas;

#pragma mark - db::const_object::impl

struct db::const_object::impl : public base::impl {
    db::model _model;
    std::string _entity_name;
    db::object_data _data;

    impl(db::model const &model, std::string const &entity_name, db::object_data const &obj_data = {})
        : _model(model), _entity_name(entity_name) {
        this->load_data(obj_data);
    }

    void clear() {
        this->_data.attributes.clear();
        this->_data.relations.clear();
    }

    void load_data(db::object_data const &obj_data) {
        this->clear();

        db::entity const &entity = this->_model.entities().at(_entity_name);

        for (auto const &pair : entity.all_attributes) {
            auto const &attr_name = pair.first;
            if (obj_data.attributes.count(attr_name) > 0) {
                this->validate_attribute_name(attr_name);

                this->_data.attributes.emplace(std::make_pair(attr_name, obj_data.attributes.at(attr_name)));
            }
        }

        for (auto const &pair : entity.relations) {
            auto const &rel_name = pair.first;
            if (obj_data.relations.count(rel_name) > 0) {
                this->validate_relation_name(rel_name);

                this->_data.relations.emplace(std::make_pair(rel_name, obj_data.relations.at(rel_name)));
            }
        }
    }

    db::value const &attribute_value(std::string const &attr_name) {
        this->validate_attribute_name(attr_name);

        if (this->_data.attributes.count(attr_name) > 0) {
            return this->_data.attributes.at(attr_name);
        }

        return db::value::null_value();
    }

    db::value_vector_t relation_ids(std::string const &rel_name) {
        this->validate_relation_name(rel_name);

        if (this->_data.relations.count(rel_name) > 0) {
            return this->_data.relations.at(rel_name);
        }
        return {};
    }

    db::value const &relation_id(std::string const &rel_name, std::size_t const idx) {
        this->validate_relation_name(rel_name);

        if (this->_data.relations.count(rel_name) > 0) {
            auto const &ids = this->_data.relations.at(rel_name);
            if (idx < ids.size()) {
                return ids.at(idx);
            }
        }
        return db::value::null_value();
    }

    std::size_t relation_size(std::string const &rel_name) {
        this->validate_relation_name(rel_name);

        if (this->_data.relations.count(rel_name) > 0) {
            return this->_data.relations.at(rel_name).size();
        }
        return 0;
    }

    db::integer_set_map_t relation_ids_for_fetch() {
        db::integer_set_map_t relation_ids;

        db::entity const &entity = this->_model.entity(_entity_name);
        for (auto const &pair : entity.relations) {
            auto const &rel_name = pair.first;
            if (this->_data.relations.count(rel_name) > 0) {
                auto const &tgt_entity_name = pair.second.target_entity_name;
                if (relation_ids.count(tgt_entity_name) == 0) {
                    relation_ids.emplace(std::make_pair(tgt_entity_name, db::integer_set_t{}));
                }

                auto &rel_id_set = relation_ids.at(tgt_entity_name);
                auto const &rel = this->_data.relations.at(rel_name);
                for (auto const &tgt_id : rel) {
                    rel_id_set.emplace(tgt_id.get<db::integer>());
                }
            }
        }

        return relation_ids;
    }

    void validate_attribute_name(std::string const &attr_name) {
        if (!this->_model.attribute_exists(this->_entity_name, attr_name)) {
            throw "attribute name (" + attr_name + ") not found in " + this->_entity_name + ".";
        }
    }

    void validate_relation_name(std::string const &rel_name) {
        if (!this->_model.relation_exists(this->_entity_name, rel_name)) {
            throw "relation name (" + rel_name + ") not found in " + this->_entity_name + ".";
        }
    }

    void validate_relation_id(db::value const &rel_id) {
        if (!rel_id || rel_id.get<db::integer>() <= 0) {
            throw "object_id not found for relation.";
        }
    }

    void validate_relation_ids(db::value_vector_t const &rel_ids) {
        for (auto const &rel_id : rel_ids) {
            this->validate_relation_id(rel_id);
        }
    }
};

#pragma mark - db::const_object

db::const_object::const_object(db::model const &model, std::string const &entity_name, db::object_data const &obj_data)
    : base(std::make_unique<impl>(model, entity_name, obj_data)) {
}

db::const_object::const_object(std::nullptr_t) : base(nullptr) {
}

db::const_object::const_object(std::shared_ptr<impl> const &impl) : base(impl) {
}

db::const_object::const_object(std::shared_ptr<impl> &&impl) : base(std::move(impl)) {
}

db::model const &db::const_object::model() const {
    return impl_ptr<impl>()->_model;
}

db::entity const &db::const_object::entity() const {
    return this->model().entity(this->entity_name());
}

std::string const &db::const_object::entity_name() const {
    return impl_ptr<impl>()->_entity_name;
}

db::value const &db::const_object::attribute_value(std::string const &attr_name) const {
    return impl_ptr<impl>()->attribute_value(attr_name);
}

db::value_vector_t db::const_object::relation_ids(std::string const &rel_name) const {
    return impl_ptr<impl>()->relation_ids(rel_name);
}

db::value const &db::const_object::relation_id(std::string const &rel_name, std::size_t const idx) const {
    return impl_ptr<impl>()->relation_id(rel_name, idx);
}

std::size_t db::const_object::relation_size(std::string const &rel_name) const {
    return impl_ptr<impl>()->relation_size(rel_name);
}

db::value const &db::const_object::object_id() const {
    return this->attribute_value(object_id_field);
}

db::value const &db::const_object::save_id() const {
    return this->attribute_value(save_id_field);
}

db::value const &db::const_object::action() const {
    return this->attribute_value(action_field);
}

db::integer_set_map_t db::const_object::relation_ids_for_fetch() const {
    return impl_ptr<impl>()->relation_ids_for_fetch();
}

db::const_object const &db::const_object::null_object() {
    static db::const_object const _null_object{nullptr};
    return _null_object;
}

#pragma mark - db::object::impl

struct db::object::impl : public const_object::impl, public manageable_object::impl {
    enum db::object_status _status = db::object_status::invalid;
    db::manager _manager;
    db::object::subject_t _subject;

    impl(db::manager const &manager, db::model const &model, std::string const &entity_name)
        : const_object::impl(model, entity_name), _manager(manager) {
    }

    ~impl() {
        if (this->_manager) {
            if (auto observable = this->_manager.object_observable()) {
                observable.object_did_erase(_entity_name, attribute_value(object_id_field).get<integer>());
            }
        }
    }

    void clear() {
        const_object::impl::clear();
        this->_status = db::object_status::invalid;
    }

    bool is_equal_to_action(std::string const &action) {
        if (this->_data.attributes.count(action_field) > 0) {
            return this->_data.attributes.at(action_field).get<db::text>() == action;
        }

        return false;
    }

    void load_data(db::object_data const &obj_data, bool const force) override {
        if (this->_status != db::object_status::changed || force) {
            this->clear();

            db::entity const &entity = this->_model.entity(_entity_name);

            for (auto const &pair : entity.all_attributes) {
                auto const &attr_name = pair.first;
                if (obj_data.attributes.count(attr_name) > 0) {
                    this->set_attribute_value(attr_name, obj_data.attributes.at(attr_name), true);
                }
            }

            for (auto const &pair : entity.relations) {
                auto const &rel_name = pair.first;
                if (obj_data.relations.count(rel_name) > 0) {
                    this->set_relation(rel_name, obj_data.relations.at(rel_name), true);
                }
            }

            if (obj_data.attributes.count(db::save_id_field) > 0) {
                this->_status = db::object_status::saved;
            }

            notify_did_change(method::loading_changed, "", false);
        }
    }

    void load_save_id(db::value const &save_id) override {
        this->set_attribute_value(db::save_id_field, save_id, true);
    }

    void load_insertion_data() override {
        this->_status = db::object_status::inserted;
        set_attribute_value(db::action_field, db::value{db::insert_action}, true);

        db::entity const &entity = _model.entity(_entity_name);

        for (auto const &pair : entity.all_attributes) {
            auto const &attr = pair.second;
            if (attr.default_value) {
                this->set_attribute_value(attr.name, attr.default_value, true);
            }
        }
    }

    void clear_data() override {
        this->clear();

        this->notify_did_change(db::object::method::loading_changed, "", false);
    }

    void set_attribute_value(std::string const &attr_name, db::value const &value, bool const loading = false) {
        this->validate_attribute_name(attr_name);

        replace(this->_data.attributes, attr_name, value);

        if (!loading) {
            if (attr_name != db::action_field) {
                this->set_update_action();
            }

            if (this->_status != db::object_status::inserted) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::attribute_changed, attr_name, true);
        }
    }

    void set_relation(std::string const &rel_name, value_vector_t const &relation_ids, bool const loading = false) {
        this->validate_relation_name(rel_name);
        this->validate_relation_ids(relation_ids);

        replace(this->_data.relations, rel_name, relation_ids);

        if (!loading) {
            this->set_update_action();

            if (this->_status != db::object_status::inserted) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name, true);
        }
    }

    void push_back_relation(std::string const &rel_name, db::value const &relation_id) {
        this->validate_relation_name(rel_name);
        this->validate_relation_id(relation_id);

        if (this->_data.relations.count(rel_name) == 0) {
            this->_data.relations.emplace(std::make_pair(rel_name, db::value_vector_t{}));
        }

        auto &vector = _data.relations.at(rel_name);
        vector.push_back(relation_id);

        this->set_update_action();

        if (this->_status != db::object_status::inserted) {
            this->_status = db::object_status::changed;
        }

        this->notify_did_change(db::object::method::relation_changed, rel_name, true);
    }

    void remove_relation_at(std::string const &rel_name, db::value const &relation_id) {
        this->validate_relation_name(rel_name);
        this->validate_relation_id(relation_id);

        if (this->_data.relations.count(rel_name) > 0) {
            erase_if(this->_data.relations.at(rel_name),
                     [relation_id](db::value const &object_id) { return object_id == relation_id; });

            this->set_update_action();

            if (this->_status != db::object_status::inserted) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name, true);
        }
    }

    void remove_relation_at(std::string const &rel_name, std::size_t const idx) {
        this->validate_relation_name(rel_name);

        if (this->_data.relations.count(rel_name) > 0) {
            auto &ids = this->_data.relations.at(rel_name);
            if (idx < ids.size()) {
                ids.erase(ids.begin() + idx);
            }

            this->set_update_action();

            if (this->_status != db::object_status::inserted) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name, true);
        }
    }

    void remove_all_relations(std::string const &rel_name) {
        this->validate_relation_name(rel_name);

        if (!this->_model.relation_exists(this->_entity_name, rel_name)) {
            throw "relation name (" + rel_name + ") not found";
        }

        if (this->_data.relations.count(rel_name) > 0) {
            this->_data.relations.erase(rel_name);

            this->set_update_action();

            if (this->_status != db::object_status::inserted) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name, true);
        }
    }

    void remove() {
        if (this->is_equal_to_action(db::remove_action)) {
            return;
        }

        erase_if(this->_data.attributes, [](auto const &pair) {
            auto const &column_name = pair.first;
            if (column_name == db::id_field || column_name == db::object_id_field || column_name == db::action_field) {
                return false;
            }
            return true;
        });

        this->_data.relations.clear();

        this->set_attribute_value(db::action_field, db::value{db::remove_action});
    }

    db::object_data data_for_save() {
        db::value_map_t attributes;
        db::value_vector_map_t relations;

        db::entity const &entity = this->_model.entity(this->_entity_name);

        for (auto const &pair : entity.all_attributes) {
            auto const &attr_name = pair.first;

            if (attr_name == db::save_id_field) {
                continue;
            }

            if (attr_name == db::object_id_field && this->_status == db::object_status::inserted) {
                continue;
            }

            if (this->_data.attributes.count(attr_name) > 0) {
                attributes.emplace(std::make_pair(attr_name, this->_data.attributes.at(attr_name)));
            } else if (pair.second.not_null) {
                attributes.emplace(std::make_pair(attr_name, pair.second.default_value));
            } else {
                attributes.emplace(std::make_pair(attr_name, db::value::null_value()));
            }
        }

        for (auto const &pair : entity.relations) {
            auto const &rel_name = pair.first;
            if (this->_data.relations.count(rel_name) > 0) {
                relations.emplace(std::make_pair(rel_name, this->_data.relations.at(rel_name)));
            }
        }

        return db::object_data{.attributes = std::move(attributes), .relations = std::move(relations)};
    }

    void set_update_action() {
        if (this->_status != db::object_status::inserted && !this->is_equal_to_action(db::remove_action) &&
            !this->is_equal_to_action(db::update_action)) {
            this->set_attribute_value(db::action_field, db::value{db::update_action}, true);
        }
    }

    void set_status(db::object_status const &stat) override {
        this->_status = stat;
    }

    void notify_did_change(db::object::method const &key, std::string const &name, bool const send_to_manager) {
        if (this->_subject.has_observer()) {
            this->_subject.notify(key, db::object::change_info{cast<db::object>(), name});
        }

        if (send_to_manager && this->_manager) {
            if (auto observable = this->_manager.object_observable()) {
                observable.object_did_change(cast<db::object>());
            }
        }
    }
};

#pragma mark - db::object::change_info

db::object::change_info::change_info(class object const &object, std::string const &name)
    : object(object), name(name){};

#pragma mark - db::object

db::object::object(db::manager const &manager, db::model const &model, std::string const &entity_name)
    : const_object(std::make_unique<impl>(manager, model, entity_name)) {
}

db::object::object(std::nullptr_t) : const_object(nullptr) {
}

db::object::subject_t const &db::object::subject() const {
    return impl_ptr<impl>()->_subject;
}

db::object::subject_t &db::object::subject() {
    return impl_ptr<impl>()->_subject;
}

void db::object::set_attribute_value(std::string const &attr_name, db::value const &value) {
    impl_ptr<impl>()->set_attribute_value(attr_name, value);
}

db::object_vector_t db::object::relation_objects(std::string const &rel_name) const {
    auto const &rel_ids = impl_ptr<impl>()->relation_ids(rel_name);
    return to_vector<db::object>(rel_ids, [manager = manager(), entity_name = entity_name()](db::value const &id) {
        return manager.cached_object(entity_name, id.get<db::integer>());
    });
}

db::object db::object::relation_object_at(std::string const &rel_name, std::size_t const idx) const {
    std::string const &tgt_entity_name = this->model().relation(entity_name(), rel_name).target_entity_name;
    return this->manager().cached_object(tgt_entity_name, relation_id(rel_name, idx).get<db::integer>());
}

void db::object::set_relation_ids(std::string const &rel_name, value_vector_t const &relation_ids) {
    impl_ptr<impl>()->set_relation(rel_name, relation_ids);
}

void db::object::add_relation_id(std::string const &rel_name, db::value const &relation_id) {
    impl_ptr<impl>()->push_back_relation(rel_name, relation_id);
}

void db::object::remove_relation_id(std::string const &rel_name, db::value const &relation_id) {
    impl_ptr<impl>()->remove_relation_at(rel_name, relation_id);
}

void db::object::set_relation_objects(std::string const &rel_name, object_vector_t const &rel_objects) {
    impl_ptr<impl>()->set_relation(
        rel_name,
        to_vector<db::value>(rel_objects, [entity_name = entity_name()](auto const &obj) { return obj.object_id(); }));
}

void db::object::add_relation_object(std::string const &rel_name, object const &rel_object) {
    impl_ptr<impl>()->push_back_relation(rel_name, rel_object.object_id());
}

void db::object::remove_relation_object(std::string const &rel_name, object const &rel_object) {
    impl_ptr<impl>()->remove_relation_at(rel_name, rel_object.object_id());
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

bool db::object::is_removed() const {
    return impl_ptr<impl>()->is_equal_to_action(remove_action);
}

db::object_data db::object::data_for_save() const {
    return impl_ptr<impl>()->data_for_save();
}

db::object const &db::object::null_object() {
    static db::object const _null_object{nullptr};
    return _null_object;
}

db::manageable_object &db::object::manageable() {
    if (!_manageable) {
        _manageable = manageable_object{impl_ptr<manageable_object::impl>()};
    }
    return _manageable;
}

std::string yas::to_string(db::object_status const &status) {
    switch (status) {
        case db::object_status::invalid:
            return "invalid";
        case db::object_status::inserted:
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
