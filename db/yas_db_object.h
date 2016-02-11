//
//  yas_db_object.h
//

#pragma once

#include <set>
#include <unordered_map>
#include "yas_base.h"
#include "yas_db_additional_protocol.h"

namespace yas {
namespace db {
    class model;
    class manager;
    class value;

    struct object_data {
        value_map attributes;
        value_vector_map relations;
    };

    using integer_set = std::set<integer::type>;
    using integer_set_map = std::unordered_map<std::string, integer_set>;

    class const_object : public base {
        using super_class = base;

       public:
        class impl;

        const_object(model const &model, std::string const &entity_name, object_data const &obj_data);
        const_object(std::nullptr_t);

        model const &model() const;
        std::string const &entity_name() const;

        value const &get_attribute(std::string const &attr_name) const;

        value_vector get_relation_ids(std::string const &rel_name) const;
        value const &get_relation_id(std::string const &rel_name, std::size_t const idx) const;
        std::size_t relation_size(std::string const &rel_name) const;

        value const &object_id() const;
        value const &save_id() const;
        value const &action() const;

        integer_set_map relation_ids_for_fetch() const;

        static const_object const &empty();

       protected:
        const_object(std::shared_ptr<impl> const &);
        const_object(std::shared_ptr<impl> &&);
    };

    static std::string const attribute_change_key = "yas.db.object.attribute_change";
    static std::string const relation_change_key = "yas.db.object.relation_change";
    static std::string const loading_change_key = "yas.db.object.loading_change";

    class object : public const_object, public manageable {
        using super_class = const_object;

       public:
        class impl;

        struct change_info {
            object const &object;
            std::string const name;

            change_info(class object const &, std::string const &);
        };

        object(manager const &manager, db::model const &model, std::string const &entity_name);
        object(std::nullptr_t);

        yas::subject<change_info> const &subject() const;
        yas::subject<change_info> &subject();

        void load_data(object_data const &obj_data);

        void set_attribute(std::string const &attr_name, value const &value);

        std::vector<db::object> get_relation_objects(std::string const &rel_name) const;
        db::object get_relation_object(std::string const &rel_name, std::size_t const idx) const;
        void set_relation_ids(std::string const &rel_name, value_vector const &relation_ids);
        void push_back_relation_id(std::string const &rel_name, value const &relation_id);
        void erase_relation_id(std::string const &rel_name, value const &relation_id);
        void set_relation_object(std::string const &rel_name, std::vector<object> const &rel_objects);
        void push_back_relation_object(std::string const &rel_name, object const &rel_object);
        void erase_relation_object(std::string const &rel_name, object const &rel_object);
        void erase_relation(std::string const &rel_name, std::size_t const idx);
        void clear_relation(std::string const &rel_name);

        manager const &manager() const;

        object_status status() const;

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
    using const_object_map = std::unordered_map<integer::type, const_object>;
    using const_object_map_map = std::unordered_map<std::string, const_object_map>;
    using const_object_vector = std::vector<const_object>;
    using const_object_vector_map = std::unordered_map<std::string, const_object_vector>;
    using weak_object_map = std::unordered_map<integer::type, weak<object>>;
    using weak_object_map_map = std::unordered_map<std::string, weak_object_map>;
    using object_data_vector = std::vector<object_data>;
    using object_data_vector_map = std::unordered_map<std::string, object_data_vector>;
}
}
