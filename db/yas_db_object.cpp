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
#include "yas_stl_utils.h"

using namespace yas;

struct db::object::impl : public base::impl {
    db::model model;
    std::string entity_name;
    db::object_data data;
    enum db::object_status status = db::object_status::invalid;
    db::manager manager;

    impl(db::manager const &manager, db::model const &model, std::string const &entity_name)
        : manager(manager), model(model), entity_name(entity_name) {
    }

    ~impl() {
        if (manager) {
            if (auto observable = dynamic_cast<object_observable *>(&manager)) {
                observable->_object_did_erase(entity_name, get_attribute(object_id_field).get<integer>());
            }
        }
    }

    void clear() {
        data.attributes.clear();
        data.relations.clear();
        status = db::object_status::invalid;
    }

    bool is_removed() {
        if (data.attributes.count(removed_field)) {
            return data.attributes.at(removed_field).get<integer>() > 0;
        }

        return false;
    }

    void load_data(object_data const &obj_data) {
        if (status != db::object_status::changed) {
            clear();

            db::entity const &entity = model.entities().at(entity_name);

            for (auto const &pair : entity.attributes) {
                auto const &attr_name = pair.first;
                if (obj_data.attributes.count(attr_name)) {
                    set_value(attr_name, obj_data.attributes.at(attr_name), true);
                }
            }

            for (auto const &pair : entity.relations) {
                auto const &rel_name = pair.first;
                if (obj_data.relations.count(rel_name)) {
                    set_relation(rel_name, obj_data.relations.at(rel_name), true);
                }
            }
        }

        status = db::object_status::saved;
    }

    db::value const &get_attribute(std::string const &attr_name) {
        validate_attribute_name(attr_name);

        if (data.attributes.count(attr_name)) {
            return data.attributes.at(attr_name);
        }

        return db::value::empty();
    }

    void set_value(std::string const &attr_name, db::value const &value, bool const loading = false) {
        validate_attribute_name(attr_name);

        if (data.attributes.count(attr_name)) {
            data.attributes.erase(attr_name);
        }
        data.attributes.emplace(std::make_pair(attr_name, value));

        status = db::object_status::changed;

        if (!loading) {
            notify_did_change();
        }
    }

    db::value_vector get_relation(std::string const &rel_name) {
        validate_relation_name(rel_name);

        if (data.relations.count(rel_name) > 0) {
            return data.relations.at(rel_name);
        }
        return {};
    }

    db::value const &get_relation(std::string const &rel_name, std::size_t const idx) {
        validate_relation_name(rel_name);

        if (data.relations.count(rel_name)) {
            auto const &ids = data.relations.at(rel_name);
            if (idx < ids.size()) {
                return ids.at(idx);
            }
        }
        return db::value::empty();
    }

    std::size_t relation_size(std::string const &rel_name) {
        validate_relation_name(rel_name);

        if (data.relations.count(rel_name)) {
            return data.relations.at(rel_name).size();
        }
        return 0;
    }

    void set_relation(std::string const &rel_name, value_vector const &relation_ids, bool const loading = false) {
        validate_relation_name(rel_name);

        if (data.relations.count(rel_name) > 0) {
            data.relations.erase(rel_name);
        }
        data.relations.emplace(std::make_pair(rel_name, relation_ids));

        status = db::object_status::changed;

        if (!loading) {
            notify_did_change();
        }
    }

    void push_back_relation(std::string const &rel_name, db::value const &relation_id) {
        validate_relation_name(rel_name);

        if (data.relations.count(rel_name) == 0) {
            data.relations.emplace(std::make_pair(rel_name, db::value_vector{}));
        }

        auto &vector = data.relations.at(rel_name);
        vector.push_back(relation_id);

        status = db::object_status::changed;

        notify_did_change();
    }

    void erase_relation(std::string const &rel_name, db::value const &relation_id) {
        validate_relation_name(rel_name);

        if (data.relations.count(rel_name)) {
            erase_if(data.relations.at(rel_name),
                     [relation_id](db::value const &object_id) { return object_id == relation_id; });

            status = db::object_status::changed;

            notify_did_change();
        }
    }

    void erase_relation(std::string const &rel_name, std::size_t const idx) {
        validate_relation_name(rel_name);

        if (data.relations.count(rel_name)) {
            auto &ids = data.relations.at(rel_name);
            if (idx < ids.size()) {
                ids.erase(ids.begin() + idx);
            }

            status = db::object_status::changed;

            notify_did_change();
        }
    }

    void clear_relation(std::string const &rel_name) {
        validate_relation_name(rel_name);

        if (model.entities().at(entity_name).relations.count(rel_name) == 0) {
            throw "relation name (" + rel_name + ") not found";
        }

        if (data.relations.count(rel_name)) {
            data.relations.erase(rel_name);
        }
    }

    void remove() {
        if (is_removed()) {
            return;
        }

        erase_if(data.attributes, [](auto const &pair) {
            auto const &column_name = pair.first;
            if (column_name == id_field || column_name == object_id_field || column_name == removed_field) {
                return false;
            }
            return true;
        });

        data.relations.clear();

        set_value(removed_field, db::value{true});
    }

    db::object_data data_for_save() {
        db::value_map attributes;
        db::value_vector_map relations;

        db::entity const &entity = model.entities().at(entity_name);

        for (auto const &pair : entity.attributes) {
            auto const &attr_name = pair.first;
            if (attr_name != save_id_field) {
                if (data.attributes.count(attr_name)) {
                    attributes.insert(std::make_pair(attr_name, data.attributes.at(attr_name)));
                } else if (pair.second.not_null) {
                    attributes.insert(std::make_pair(attr_name, pair.second.default_value));
                } else {
                    attributes.insert(std::make_pair(attr_name, db::value::empty()));
                }
            }
        }

        for (auto const &pair : entity.relations) {
            auto const &rel_name = pair.first;
            if (data.relations.count(rel_name)) {
                relations.insert(std::make_pair(rel_name, data.relations.at(rel_name)));
            }
        }

        return object_data{.attributes = std::move(attributes), .relations = std::move(relations)};
    }

    integer_set_map relation_ids_for_fetch() {
        integer_set_map relation_ids;

        db::entity const &entity = model.entities().at(entity_name);
        for (auto const &pair : entity.relations) {
            auto const &rel_name = pair.first;
            if (data.relations.count(rel_name)) {
                auto const &tgt_entity_name = pair.second.target_entity_name;
                if (relation_ids.count(tgt_entity_name) == 0) {
                    relation_ids.emplace(std::make_pair(tgt_entity_name, integer_set{}));
                }

                auto &rel_id_set = relation_ids.at(tgt_entity_name);
                auto const &rel = data.relations.at(rel_name);
                for (auto const &tgt_id : rel) {
                    rel_id_set.insert(tgt_id.get<integer>());
                }
            }
        }

        return relation_ids;
    }

    void notify_did_change() {
        if (manager) {
            if (auto observable = dynamic_cast<object_observable *>(&manager)) {
                observable->_object_did_change(cast<db::object>());
            }
        }
    }

    void validate_attribute_name(std::string const &attr_name) {
        if (model.entities().at(entity_name).attributes.count(attr_name) == 0) {
            throw "attribute name (" + attr_name + ") not found in " + entity_name + ".";
        }
    }

    void validate_relation_name(std::string const &rel_name) {
        if (model.entities().at(entity_name).relations.count(rel_name) == 0) {
            throw "relation name (" + rel_name + ") not found in " + entity_name + ".";
        }
    }
};

db::object::object(db::manager const &manager, db::model const &model, std::string const &entity_name)
    : super_class(std::make_unique<impl>(manager, model, entity_name)) {
}

db::object::object(std::nullptr_t) : super_class(nullptr) {
}

void db::object::load_data(object_data const &obj_data) {
    impl_ptr<impl>()->load_data(obj_data);
}

db::value const &db::object::get_attribute(std::string const &attr_name) const {
    return impl_ptr<impl>()->get_attribute(attr_name);
}

void db::object::set_value(std::string const &attr_name, db::value const &value) {
    impl_ptr<impl>()->set_value(attr_name, value);
}

db::value_vector db::object::get_relation_ids(std::string const &rel_name) const {
    return impl_ptr<impl>()->get_relation(rel_name);
}

db::value const &db::object::get_relation_id(std::string const &rel_name, std::size_t const idx) const {
    return impl_ptr<impl>()->get_relation(rel_name, idx);
}

std::vector<db::object> db::object::get_relation_objects(std::string const &rel_name) const {
    auto const &rel_ids = impl_ptr<impl>()->get_relation(rel_name);
    return map<db::object>(rel_ids, [manager = manager(), entity_name = entity_name()](db::value const &id) {
        return manager.cached_object(entity_name, id.get<integer>());
    });
}

db::object db::object::get_relation_object(std::string const &rel_name, std::size_t const idx) const {
    std::string const &tgt_entity_name = model().entities().at(entity_name()).relations.at(rel_name).target_entity_name;
    return manager().cached_object(tgt_entity_name, get_relation_id(rel_name, idx).get<integer>());
}

std::size_t db::object::relation_size(std::string const &rel_name) const {
    return impl_ptr<impl>()->relation_size(rel_name);
}

void db::object::set_relation_ids(std::string const &rel_name, value_vector const &relation_ids) {
    impl_ptr<impl>()->set_relation(rel_name, relation_ids);
}

void db::object::push_back_relation_id(std::string const &rel_name, db::value const &relation_id) {
    impl_ptr<impl>()->push_back_relation(rel_name, relation_id);
}

void db::object::erase_relation_id(std::string const &rel_name, db::value const &relation_id) {
    impl_ptr<impl>()->erase_relation(rel_name, relation_id);
}

void db::object::set_relation_object(std::string const &rel_name, object_vector const &rel_objects) {
    impl_ptr<impl>()->set_relation(
        rel_name,
        map<db::value>(rel_objects, [entity_name = entity_name()](auto const &obj) { return obj.object_id(); }));
}

void db::object::push_back_relation_object(std::string const &rel_name, object const &rel_object) {
    impl_ptr<impl>()->push_back_relation(rel_name, rel_object.object_id());
}

void db::object::erase_relation_object(std::string const &rel_name, object const &rel_object) {
    impl_ptr<impl>()->erase_relation(rel_name, rel_object.object_id());
}

void db::object::erase_relation(std::string const &rel_name, std::size_t const idx) {
    impl_ptr<impl>()->erase_relation(rel_name, idx);
}

void db::object::clear_relation(std::string const &rel_name) {
    impl_ptr<impl>()->clear_relation(rel_name);
}

db::manager const &db::object::manager() const {
    return impl_ptr<impl>()->manager;
}

db::model const &db::object::model() const {
    return impl_ptr<impl>()->model;
}

std::string const &db::object::entity_name() const {
    return impl_ptr<impl>()->entity_name;
}

enum db::object_status db::object::status() const {
    return impl_ptr<impl>()->status;
}

void db::object::set_status(object_status const &stat) {
    impl_ptr<impl>()->status = stat;
}

db::value const &db::object::object_id() const {
    return get_attribute(object_id_field);
}

db::value const &db::object::save_id() const {
    return get_attribute(save_id_field);
}

void db::object::remove() {
    impl_ptr<impl>()->remove();
}

bool db::object::is_removed() const {
    return impl_ptr<impl>()->is_removed();
}

db::object_data db::object::data_for_save() const {
    return impl_ptr<impl>()->data_for_save();
}

db::integer_set_map db::object::relation_ids_for_fetch() const {
    return impl_ptr<impl>()->relation_ids_for_fetch();
}

db::object const &db::object::empty() {
    static db::object const _empty_object{nullptr};
    return _empty_object;
}

#pragma mark -

db::integer_set_map db::relation_ids(db::object_vector_map const &objects) {
    db::integer_set_map rel_ids;

    for (auto const &entity_pair : objects) {
        for (auto const &object : entity_pair.second) {
            auto obj_rel_ids = object.relation_ids_for_fetch();
            for (auto &obj_rel_pair : obj_rel_ids) {
                auto const &entity_name = obj_rel_pair.first;
                if (rel_ids.count(entity_name) == 0) {
                    rel_ids.emplace(std::make_pair(entity_name, integer_set{}));
                }

                for (auto &tgt_id : obj_rel_pair.second) {
                    rel_ids.at(entity_name).emplace(tgt_id);
                }
            }
        }
    }

    return rel_ids;
}
