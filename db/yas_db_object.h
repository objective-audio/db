//
//  yas_db_object.h
//

#pragma once

#include <deque>
#include <set>
#include <unordered_map>
#include <experimental/optional>
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
    class entity;

    using integer_set_t = std::set<db::integer::type>;
    using integer_set_map_t = std::unordered_map<std::string, db::integer_set_t>;

    using object_map_t = std::unordered_map<db::integer::type, object>;
    using object_map_map_t = std::unordered_map<std::string, db::object_map_t>;
    using object_vector_t = std::vector<db::object>;
    using object_vector_map_t = std::unordered_map<std::string, db::object_vector_t>;
    using object_deque_t = std::deque<db::object>;
    using object_deque_map_t = std::unordered_map<std::string, db::object_deque_t>;
    using const_object_map_t = std::unordered_map<db::integer::type, db::const_object>;
    using const_object_map_map_t = std::unordered_map<std::string, db::const_object_map_t>;
    using const_object_vector_t = std::vector<db::const_object>;
    using const_object_vector_map_t = std::unordered_map<std::string, db::const_object_vector_t>;
    using weak_object_map_t = std::unordered_map<db::integer::type, weak<db::object>>;
    using weak_object_map_map_t = std::unordered_map<std::string, db::weak_object_map_t>;
    using object_data_vector_t = std::vector<db::object_data>;
    using object_data_vector_map_t = std::unordered_map<std::string, db::object_data_vector_t>;

    class const_object : public base {
       public:
        class impl;

        const_object(db::entity const &entity, db::object_data const &obj_data);
        const_object(std::nullptr_t);

        db::entity const &entity() const;
        std::string const &entity_name() const;

        db::value const &attribute_value(std::string const &attr_name) const;

        db::value_vector_t relation_ids(std::string const &rel_name) const;
        db::value const &relation_id(std::string const &rel_name, std::size_t const idx) const;
        std::size_t relation_size(std::string const &rel_name) const;

        db::value const &object_id() const;
        db::value const &save_id() const;
        db::value const &action() const;

        bool is_inserted() const;
        bool is_updated() const;
        bool is_removed() const;

        bool is_temporary() const;

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
        enum class change_reason { replaced, inserted, removed };

        struct relation_change_info {
            db::object::change_reason const reason;
            std::vector<std::size_t> const indices;
        };

        struct change_info {
            db::object const &object;
            std::string const name;

            change_info(db::object const &, std::string const &);
            change_info(db::object const &, std::string const &, relation_change_info &&rel_change_info);

            db::object::relation_change_info const &relation_change_info() const;

           private:
            std::experimental::optional<db::object::relation_change_info> const _rel_change_info;
        };

        using subject_t = subject<change_info, method>;
        using observer_t = observer<change_info, method>;

        object(db::manager const &manager, db::entity const &entity);
        object(std::nullptr_t);

        subject_t const &subject() const;
        subject_t &subject();

        void set_attribute_value(std::string const &attr_name, db::value const &value);

        db::object_vector_t relation_objects(std::string const &rel_name) const;
        db::object relation_object_at(std::string const &rel_name, std::size_t const idx) const;

        void set_relation_ids(std::string const &rel_name, db::value_vector_t const &relation_ids);
        void add_relation_id(std::string const &rel_name, db::value const &relation_id);
        void insert_relation_id(std::string const &rel_name, db::value const &relation_id, std::size_t const idx);
        void remove_relation_id(std::string const &rel_name, db::value const &relation_id);
        void set_relation_objects(std::string const &rel_name, db::object_vector_t const &rel_objects);
        void add_relation_object(std::string const &rel_name, db::object const &rel_object);
        void insert_relation_object(std::string const &rel_name, db::object const &rel_object, std::size_t const idx);
        void remove_relation_object(std::string const &rel_name, db::object const &rel_object);
        void remove_relation_at(std::string const &rel_name, std::size_t const idx);
        void remove_all_relations(std::string const &rel_name);

        db::manager const &manager() const;

        db::object_status status() const;

        void remove();

        db::object_data data_for_save() const;

        static db::object const &null_object();

        db::manageable_object &manageable();

       private:
        db::manageable_object _manageable = nullptr;
    };
}

std::string to_string(db::object_status const &);
}
