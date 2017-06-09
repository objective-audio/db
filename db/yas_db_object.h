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
    class manager;
    class entity;
    class identifier;

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

        db::identifier const &identifier() const;
        db::value const &object_id() const;
        db::value const &save_id() const;
        db::value const &action() const;

        bool is_inserted() const;
        bool is_updated() const;
        bool is_removed() const;

        bool is_temporary() const;

        db::integer_set_map_t relation_ids_for_fetch() const;

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

        object(db::manager const &manager, db::entity const &entity, bool const is_temporary = false);
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

        db::manageable_object &manageable();

       private:
        db::manageable_object _manageable = nullptr;
    };

    db::const_object const &null_const_object();
    db::object const &null_object();

    db::value const &insert_action_value();
    db::value const &update_action_value();
    db::value const &remove_action_value();
}

std::string to_string(db::object_status const &);
}
