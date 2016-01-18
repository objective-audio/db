//
//  yas_db_object.h
//

#pragma once

#include <unordered_map>
#include "yas_base.h"
#include "yas_db_additional_protocol.h"

namespace yas {
namespace db {
    class model;
    class manager;
    class value;

    class object : public base, public manageable {
        using super_class = base;

       public:
        class impl;

        object(manager const &manager, model const &model, std::string const &entity_name);
        object(std::nullptr_t);

        void load(value_map const &values);

        value const &get(std::string const &attr_name) const;
        void set(std::string const &attr_name, value const &value);

        manager const &manager() const;
        model const &model() const;
        std::string const &entity_name() const;

        object_status status() const;

        value const &object_id() const;
        value const &save_id() const;

        void remove();
        bool is_removed() const;

        value_map values_for_save() const;

        static object const &empty();

       private:
        void set_status(object_status const &);
    };

    using object_map = std::unordered_map<integer::type, object>;
    using object_map_map = std::unordered_map<std::string, object_map>;
    using object_vector = std::vector<object>;
    using object_vector_map = std::unordered_map<std::string, object_vector>;
    using weak_object_map = std::unordered_map<integer::type, weak<object>>;
    using weak_object_map_map = std::unordered_map<std::string, weak_object_map>;
}
}
