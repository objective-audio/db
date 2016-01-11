//
//  yas_db_object.cpp
//

#include "yas_db_entity.h"
#include "yas_db_model.h"
#include "yas_db_object.h"
#include "yas_stl_utils.h"

using namespace yas;

struct db::object::impl : public base::impl {
    db::model model;
    std::string entity_name;
    db::column_map values;
    enum db::object::status status;

    impl(db::model const &model, std::string const &entity_name)
        : model(model), entity_name(entity_name), status(db::object::status::invalid) {
    }

    void clear() {
        values.clear();
        status = db::object::status::invalid;
    }

    bool is_removed() {
        if (values.count(removed_field)) {
            return values.at(removed_field).get<integer>() > 0;
        }

        return false;
    }

    void load(db::column_map const &vals) {
        clear();

        db::entity const &entity = model.entities().at(entity_name);
        for (auto const &pair : entity.attributes) {
            auto const &attr_name = pair.first;
            if (vals.count(attr_name)) {
                set(attr_name, vals.at(attr_name));
            }
        }

        status = db::object::status::saved;
    }

    db::value const &get(std::string const &column_name) {
        if (values.count(column_name)) {
            return values.at(column_name);
        }

        return db::value::empty();
    }

    void set(std::string const &attr_name, db::value const &value) {
        if (values.count(attr_name)) {
            values.erase(attr_name);
        }
        values.emplace(std::make_pair(attr_name, value));

        status = db::object::status::changed;
    }

    void remove() {
        if (is_removed()) {
            return;
        }

        erase_if(values, [](auto const &pair) {
            auto const &column_name = pair.first;
            if (column_name == id_field || column_name == object_id_field || column_name == removed_field) {
                return false;
            }
            return true;
        });

        set(removed_field, db::value{true});
    }

    db::column_map parameters() {
        db::column_map params;

        db::entity const &entity = model.entities().at(entity_name);
        for (auto const &pair : entity.attributes) {
            auto const &attr_name = pair.first;
            if (values.count(attr_name)) {
                params.insert(std::make_pair(attr_name, values.at(attr_name)));
            } else {
                params.insert(std::make_pair(attr_name, pair.second.default_value));
            }
        }

        return params;
    }
};

db::object::object(db::model const &model, std::string const &entity_name)
    : super_class(std::make_unique<impl>(model, entity_name)) {
}

db::object::object(std::nullptr_t) : super_class(nullptr) {
}

void db::object::load(db::column_map const &values) {
    impl_ptr<impl>()->load(values);
}

db::value const &db::object::get(std::string const &attr_name) const {
    return impl_ptr<impl>()->get(attr_name);
}

void db::object::set(std::string const &attr_name, db::value const &value) {
    impl_ptr<impl>()->set(attr_name, value);
}

db::model const &db::object::model() const {
    return impl_ptr<impl>()->model;
}

std::string const &db::object::entity_name() const {
    return impl_ptr<impl>()->entity_name;
}

enum db::object::status db::object::status() const {
    return impl_ptr<impl>()->status;
}

db::value const &db::object::object_id() const {
    return get(object_id_field);
}

db::value const &db::object::save_id() const {
    return get(save_id_field);
}

void db::object::remove() {
    impl_ptr<impl>()->remove();
}

bool db::object::is_removed() const {
    return impl_ptr<impl>()->is_removed();
}

db::column_map db::object::parameters() const {
    return impl_ptr<impl>()->parameters();
}

db::object const &db::object::empty() {
    static db::object const _empty_object{nullptr};
    return _empty_object;
}
