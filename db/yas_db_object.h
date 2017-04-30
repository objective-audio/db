//
//  yas_db_object.h
//

#pragma once

#include <deque>
#include <set>
#include <unordered_map>
#include "yas_base.h"
#include "yas_db_additional_protocol.h"

namespace yas {
template <typename T, typename K>
class subject;
template <typename T, typename K>
class observer;

namespace db {
    class model;
    class manager;
    class value;
    class const_object;
    class object;

    using integer_set_t = std::set<integer::type>;
    using integer_set_map_t = std::unordered_map<std::string, integer_set_t>;

    using object_map_t = std::unordered_map<integer::type, object>;
    using object_map_map_t = std::unordered_map<std::string, object_map_t>;
    using object_vector_t = std::vector<object>;
    using object_vector_map_t = std::unordered_map<std::string, object_vector_t>;
    using object_deque_t = std::deque<object>;
    using object_deque_map_t = std::unordered_map<std::string, object_deque_t>;
    using const_object_map_t = std::unordered_map<integer::type, const_object>;
    using const_object_map_map_t = std::unordered_map<std::string, const_object_map_t>;
    using const_object_vector_t = std::vector<const_object>;
    using const_object_vector_map_t = std::unordered_map<std::string, const_object_vector_t>;
    using weak_object_map_t = std::unordered_map<integer::type, weak<object>>;
    using weak_object_map_map_t = std::unordered_map<std::string, weak_object_map_t>;
    using object_data_vector_t = std::vector<object_data>;
    using object_data_vector_map_t = std::unordered_map<std::string, object_data_vector_t>;

    class const_object : public base {
       public:
        class impl;

        const_object(model const &model, std::string const &entity_name, db::object_data const &obj_data);
        const_object(std::nullptr_t);

        db::model const &model() const;
        std::string const &entity_name() const;

        db::value const &get_attribute(std::string const &attr_name) const;

        db::value_vector_t get_relation_ids(std::string const &rel_name) const;
        db::value const &get_relation_id(std::string const &rel_name, std::size_t const idx) const;
        std::size_t relation_size(std::string const &rel_name) const;

        db::value const &object_id() const;
        db::value const &save_id() const;
        db::value const &action() const;

        db::integer_set_map_t relation_ids_for_fetch() const;

        static db::const_object const &null_object();

       protected:
        const_object(std::shared_ptr<impl> const &);
        const_object(std::shared_ptr<impl> &&);
    };

    class object : public const_object {
       public:
        class impl;

        enum class method { attribute_changed, relation_changed, loading_changed };

        struct change_info {
            db::object const &object;
            std::string const name;

            change_info(db::object const &, std::string const &);
        };

        using subject_t = subject<change_info, method>;
        using observer_t = observer<change_info, method>;

        object(manager const &manager, db::model const &model, std::string const &entity_name);
        object(std::nullptr_t);

        subject_t const &subject() const;
        subject_t &subject();

        void set_attribute(std::string const &attr_name, value const &value);

        db::object_vector_t get_relation_objects(std::string const &rel_name) const;
        db::object get_relation_object(std::string const &rel_name, std::size_t const idx) const;
        void set_relation_ids(std::string const &rel_name, db::value_vector_t const &relation_ids);
        void push_back_relation_id(std::string const &rel_name, db::value const &relation_id);
        void erase_relation_id(std::string const &rel_name, db::value const &relation_id);
        void set_relation_objects(std::string const &rel_name, db::object_vector_t const &rel_objects);
        void push_back_relation_object(std::string const &rel_name, db::object const &rel_object);
        void erase_relation_object(std::string const &rel_name, db::object const &rel_object);
        void erase_relation(std::string const &rel_name, std::size_t const idx);
        void clear_relation(std::string const &rel_name);

        manager const &manager() const;

        db::object_status status() const;

        void remove();
        bool is_removed() const;

        db::object_data data_for_save() const;

        static db::object const &null_object();

        db::manageable_object &manageable();

       private:
        db::manageable_object _manageable = nullptr;
    };
}

std::string to_string(db::object_status const &);
}
