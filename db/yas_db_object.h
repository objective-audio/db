//
//  yas_db_object.h
//

#pragma once

#include <unordered_map>
#include "yas_base.h"
#include "yas_db_additional_protocol.h"
#include "yas_db_value.h"

namespace yas {
namespace db {
    class model;

    class object : public base, public object_manageable {
        using super_class = base;

       public:
        object(model const &model, std::string const &entity_name);
        object(std::nullptr_t);

        void load(db::value_map const &values);

        value const &get(std::string const &attr_name) const;
        void set(std::string const &attr_name, value const &value);

        model const &model() const;
        std::string const &entity_name() const;

        object_status status() const;

        db::value const &object_id() const;
        db::value const &save_id() const;

        void remove();
        bool is_removed() const;

        db::value_map parameters_for_save() const;

        static db::object const &empty();

       private:
        class impl;

        void set_status(object_status const &);
    };

    using object_map = std::unordered_map<db::integer::type, object>;
    using entity_objects_map = std::unordered_map<std::string, object_map>;
}
}
