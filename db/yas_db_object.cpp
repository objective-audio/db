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
#include "yas_db_object_id.h"
#include "yas_observing.h"
#include "yas_stl_utils.h"
#include "yas_fast_each.h"
#include "yas_db_additional_utils.h"

using namespace yas;

#pragma mark - db::const_object::impl

struct db::const_object::impl : public base::impl {
    db::entity _entity;
    db::value_map_t _attributes;
    db::id_vector_map_t _relations;
    db::object_id _identifier;

    // const_objectとして作る場合
    impl(db::entity const &entity, db::object_data const &obj_data = {}) : _entity(entity), _identifier(nullptr) {
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
            auto const &attr_name = pair.first;
            if (obj_data.attributes.count(attr_name) > 0) {
                this->validate_attribute_name(attr_name);

                this->_attributes.emplace(attr_name, obj_data.attributes.at(attr_name));
            }
        }

        for (auto const &pair : this->_entity.relations) {
            auto const &rel_name = pair.first;
            if (obj_data.relations.count(rel_name) > 0) {
                this->validate_relation_name(rel_name);

                this->_relations.emplace(rel_name, db::to_stable_ids(obj_data.relations.at(rel_name)));
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

    db::value_vector_t relation_ids(std::string const &rel_name) {
        this->validate_relation_name(rel_name);

        if (this->_relations.count(rel_name) > 0) {
            return db::to_values(this->_relations.at(rel_name));
        }
        return {};
    }

    db::value const &relation_id(std::string const &rel_name, std::size_t const idx) {
        this->validate_relation_name(rel_name);

        if (this->_relations.count(rel_name) > 0) {
            auto const &ids = this->_relations.at(rel_name);
            if (idx < ids.size()) {
                return ids.at(idx).stable();
            }
        }
        return db::null_value();
    }

    std::size_t relation_size(std::string const &rel_name) {
        this->validate_relation_name(rel_name);

        if (this->_relations.count(rel_name) > 0) {
            return this->_relations.at(rel_name).size();
        }
        return 0;
    }

    db::integer_set_map_t relation_ids_for_fetch() {
        db::integer_set_map_t relation_ids;

        for (auto const &pair : this->_entity.relations) {
            auto const &rel_name = pair.first;
            if (this->_relations.count(rel_name) > 0) {
                auto const &tgt_entity_name = pair.second.target_entity_name;
                if (relation_ids.count(tgt_entity_name) == 0) {
                    relation_ids.emplace(tgt_entity_name, db::integer_set_t{});
                }

                auto &rel_id_set = relation_ids.at(tgt_entity_name);
                auto const &rel = this->_relations.at(rel_name);
                for (auto const &tgt_obj_id : rel) {
                    rel_id_set.emplace(tgt_obj_id.stable().get<db::integer>());
                }
            }
        }

        return relation_ids;
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

    void update_identifier(db::value stable) {
        if (this->_identifier) {
            this->_identifier.set_stable(std::move(stable));
        } else {
            this->_identifier = db::make_stable_id(std::move(stable));
        }
    }

    void update_identifier(db::object_data const &obj_data) {
        if (obj_data.attributes.count(db::object_id_field)) {
            this->update_identifier(obj_data.attributes.at(db::object_id_field));
        } else {
            throw std::invalid_argument("object_id not found in object_data.");
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

db::value_vector_t db::const_object::relation_ids(std::string const &rel_name) const {
    return impl_ptr<impl>()->relation_ids(rel_name);
}

db::value const &db::const_object::relation_id(std::string const &rel_name, std::size_t const idx) const {
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

db::integer_set_map_t db::const_object::relation_ids_for_fetch() const {
    return impl_ptr<impl>()->relation_ids_for_fetch();
}

#pragma mark - db::object::impl

struct db::object::impl : public const_object::impl, public manageable_object::impl {
    enum db::object_status _status = db::object_status::invalid;
    db::manager _manager;
    db::object::subject_t _subject;

    impl(db::manager const &manager, db::entity const &entity, bool const is_temporary)
        : const_object::impl(entity, db::make_temporary_id()), _manager(manager) {
    }

    ~impl() {
        if (this->_manager) {
            if (auto observable = this->_manager.object_observable()) {
                observable.object_did_erase(_entity.name, this->_identifier);
            }
        }
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
                auto const &attr_name = pair.first;
                if (obj_data.attributes.count(attr_name) > 0) {
                    this->set_attribute_value(attr_name, obj_data.attributes.at(attr_name), true);
                }
            }

            for (auto const &pair : this->_entity.relations) {
                auto const &rel_name = pair.first;
                if (obj_data.relations.count(rel_name) > 0) {
                    this->set_relation_ids(rel_name, obj_data.relations.at(rel_name), true);
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
        set_attribute_value(db::action_field, db::insert_action_value(), true);

        for (auto const &pair : this->_entity.all_attributes) {
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
        if (attr_name == db::object_id_field) {
            return;
        }

        this->validate_attribute_name(attr_name);

        replace(this->_attributes, attr_name, value);

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

    void set_relation_ids(std::string const &rel_name, value_vector_t const &relation_ids, bool const loading = false) {
        this->validate_relation_name(rel_name);
        this->validate_relation_ids(relation_ids);

        replace(this->_relations, rel_name, db::to_stable_ids(relation_ids));

        if (!loading) {
            this->set_update_action();

            if (this->_status != db::object_status::inserted) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name, {change_reason::replaced, {}},
                                    true);
        }
    }

    void add_relation_id(std::string const &rel_name, db::value const &rel_id) {
        if (this->_relations.count(rel_name) > 0) {
            this->insert_relation_id(rel_name, rel_id, this->_relations.at(rel_name).size());
        } else {
            this->insert_relation_id(rel_name, rel_id, 0);
        }
    }

    void insert_relation_id(std::string const &rel_name, db::value const &relation_id, std::size_t const idx) {
        this->validate_relation_name(rel_name);
        this->validate_relation_id(relation_id);

        if (this->_relations.count(rel_name) == 0) {
            this->_relations.emplace(rel_name, db::id_vector_t{});
        }

        auto &vector = _relations.at(rel_name);
        vector.insert(vector.begin() + idx, db::make_stable_id(relation_id));

        this->set_update_action();

        if (this->_status != db::object_status::inserted) {
            this->_status = db::object_status::changed;
        }

        this->notify_did_change(db::object::method::relation_changed, rel_name, {change_reason::inserted, {idx}}, true);
    }

    void remove_relation_id(std::string const &rel_name, db::value const &relation_id) {
        this->validate_relation_name(rel_name);
        this->validate_relation_id(relation_id);

        if (this->_relations.count(rel_name) > 0) {
            std::size_t idx = 0;
            std::vector<std::size_t> indices;

            erase_if(this->_relations.at(rel_name), [relation_id, &idx, &indices](db::object_id const &object_id) {
                bool const result = object_id.stable() == relation_id;
                if (result) {
                    indices.push_back(idx);
                }
                ++idx;
                return result;
            });

            this->set_update_action();

            if (this->_status != db::object_status::inserted) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name,
                                    {change_reason::removed, std::move(indices)}, true);
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

            if (this->_status != db::object_status::inserted) {
                this->_status = db::object_status::changed;
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name, {change_reason::removed, {idx}},
                                    true);
        }
    }

    void remove_all_relations(std::string const &rel_name) {
        this->validate_relation_name(rel_name);

        if (this->_entity.relations.count(rel_name) == 0) {
            throw "relation name (" + rel_name + ") not found";
        }

        if (this->_relations.count(rel_name) > 0) {
            auto const rel_size = this->_relations.at(rel_name).size();

            this->_relations.erase(rel_name);

            this->set_update_action();

            if (this->_status != db::object_status::inserted) {
                this->_status = db::object_status::changed;
            }

            std::vector<std::size_t> indices;
            indices.reserve(rel_size);
            auto each = make_fast_each(rel_size);
            while (yas_each_next(each)) {
                indices.push_back(yas_each_index(each));
            }

            this->notify_did_change(db::object::method::relation_changed, rel_name,
                                    {change_reason::removed, std::move(indices)}, true);
        }
    }

    void remove() {
        if (this->is_equal_to_action(db::remove_action)) {
            return;
        }

        erase_if(this->_attributes, [](auto const &pair) {
            auto const &column_name = pair.first;
            if (column_name == db::pk_id_field || column_name == db::object_id_field ||
                column_name == db::action_field) {
                return false;
            }
            return true;
        });

        this->_relations.clear();

        this->set_attribute_value(db::action_field, db::remove_action_value());
    }

    db::object_save_data data_for_save() {
        db::value_map_t attributes;
        db::id_vector_map_t relations;

#warning insertedな時にstableなことがあるのはなぜか？
        if (this->_status != db::object_status::inserted) {
            attributes.emplace(db::object_id_field, this->_identifier.stable());
        }

        for (auto const &pair : this->_entity.all_attributes) {
            auto const &attr_name = pair.first;

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
            auto const &rel_name = pair.first;
            if (this->_relations.count(rel_name) > 0) {
                relations.emplace(rel_name, db::copy_ids(this->_relations.at(rel_name)));
            }
        }

        return db::object_save_data{.object_id = this->_identifier.copy(),
                                    .attributes = std::move(attributes),
                                    .relations = std::move(relations)};
    }

    void set_update_action() {
        if (this->_status != db::object_status::inserted && !this->is_equal_to_action(db::remove_action) &&
            !this->is_equal_to_action(db::update_action)) {
            this->set_attribute_value(db::action_field, db::update_action_value(), true);
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

    void notify_did_change(db::object::method const &key, std::string const &name,
                           db::object::relation_change_info &&rel_change_info, bool const send_to_manager) {
        if (this->_subject.has_observer()) {
            this->_subject.notify(key, db::object::change_info{cast<db::object>(), name, std::move(rel_change_info)});
        }

        if (send_to_manager && this->_manager) {
            if (auto observable = this->_manager.object_observable()) {
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
    std::string const &tgt_entity_name = this->entity().relations.at(rel_name).target_entity_name;
    return to_vector<db::object>(rel_ids, [manager = manager(), &tgt_entity_name](db::value const &id) {
#warning object_idはrelationが直接持っているのを使いたい
        return manager.cached_object(tgt_entity_name, db::make_stable_id(id));
    });
}

db::object db::object::relation_object_at(std::string const &rel_name, std::size_t const idx) const {
    std::string const &tgt_entity_name = this->entity().relations.at(rel_name).target_entity_name;
#warning object_idはrelationが直接持っているのを使いたい
    return this->manager().cached_object(tgt_entity_name, db::make_stable_id(relation_id(rel_name, idx)));
}

void db::object::set_relation_ids(std::string const &rel_name, value_vector_t const &relation_ids) {
    impl_ptr<impl>()->set_relation_ids(rel_name, relation_ids);
}

void db::object::add_relation_id(std::string const &rel_name, db::value const &rel_id) {
    impl_ptr<impl>()->add_relation_id(rel_name, rel_id);
}

void db::object::insert_relation_id(std::string const &rel_name, db::value const &rel_id, std::size_t const idx) {
    impl_ptr<impl>()->insert_relation_id(rel_name, rel_id, idx);
}

void db::object::remove_relation_id(std::string const &rel_name, db::value const &rel_id) {
    impl_ptr<impl>()->remove_relation_id(rel_name, rel_id);
}

void db::object::set_relation_objects(std::string const &rel_name, object_vector_t const &rel_objects) {
    impl_ptr<impl>()->set_relation_ids(
        rel_name, to_vector<db::value>(rel_objects, [entity_name = entity_name()](auto const &obj) {
            return obj.object_id().stable();
        }));
}

void db::object::add_relation_object(std::string const &rel_name, object const &rel_object) {
    impl_ptr<impl>()->add_relation_id(rel_name, rel_object.object_id().stable());
}

void db::object::insert_relation_object(std::string const &rel_name, db::object const &rel_object,
                                        std::size_t const idx) {
    impl_ptr<impl>()->insert_relation_id(rel_name, rel_object.object_id().stable(), idx);
}

void db::object::remove_relation_object(std::string const &rel_name, object const &rel_object) {
    impl_ptr<impl>()->remove_relation_id(rel_name, rel_object.object_id().stable());
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

db::object_save_data db::object::data_for_save() const {
    return impl_ptr<impl>()->data_for_save();
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
