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

    struct object_data {
        value_map values;
        value_vector_map relations;
    };

    class object : public base, public manageable {
        using super_class = base;

       public:
        class impl;

        object(manager const &manager, model const &model, std::string const &entity_name);
        object(std::nullptr_t);

        void load_data(object_data const &obj_data);

        value const &get_value(std::string const &attr_name) const;
        void set_value(std::string const &attr_name, value const &value);

        value_vector get_relation(std::string const &rel_name) const;
        value const &get_relation(std::string const &rel_name, std::size_t const idx) const;
        std::size_t relation_size(std::string const &rel_name) const;
        void set_relation(std::string const &rel_name, value_vector const &relation_ids);
        void push_back_relation(std::string const &rel_name, value const &relation_id);
        void erase_relation(std::string const &rel_name, value const &relation_id);
        void erase_relation(std::string const &rel_name, std::size_t const idx);
        void clear_relation(std::string const &rel_name);

        manager const &manager() const;
        model const &model() const;
        std::string const &entity_name() const;

        object_status status() const;

        value const &object_id() const;
        value const &save_id() const;

        void remove();
        bool is_removed() const;

        object_data data_for_save() const;

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
    using object_data_vector = std::vector<object_data>;
    using object_data_vector_map = std::unordered_map<std::string, object_data_vector>;
}
}
