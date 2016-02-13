//
//  yas_db_manager.h
//

#pragma once

#include "yas_base.h"
#include "yas_db_additional_protocol.h"
#include "yas_db_database.h"
#include "yas_db_object.h"

namespace yas {
class operation;

namespace db {
    class select_option;
    class model;
    class error;

    using entity_count_map = std::unordered_map<std::string, std::size_t>;

    class manager : public base, public object_observable {
        using super_class = base;

       public:
        class impl;

        enum class error_type {
            none,

            begin_transaction_failed,

            create_info_table_failed,
            create_entity_table_failed,
            alter_entity_table_failed,
            create_relation_table_failed,
            create_index_failed,

            insert_info_failed,
            insert_attributes_failed,
            insert_relation_failed,

            update_info_failed,
            update_save_id_failed,

            select_failed,
            select_info_failed,
            select_last_failed,
            select_revert_failed,

            fetch_object_datas_failed,

            delete_failed,

            invalid_version_text,
            version_not_found,
            save_id_not_found,
            out_of_range_save_id,

        };

        struct error {
            error(std::nullptr_t);
            explicit error(error_type const error_type, db::error db_error = nullptr);

            explicit operator bool() const;

            error_type const &type() const;
            db::error const &database_error() const;

           private:
            error_type _type;
            db::error _db_error;
        };

        using priority_t = UInt32;

        using state_t = result<std::nullptr_t, error>;
        using vector_result_t = result<object_vector_map, error>;
        using map_result_t = result<object_map_map, error>;
        using const_vector_result_t = result<const_object_vector_map, error>;
        using const_map_result_t = result<const_object_map_map, error>;

        using execution_f = std::function<void(manager &, operation const &)>;

        using insert_prepare_f = std::function<entity_count_map(manager &)>;
        using fetch_prepare_f = std::function<integer_set_map(manager &)>;

        using vector_completion_f = std::function<void(manager &, vector_result_t)>;
        using map_completion_f = std::function<void(manager &, map_result_t)>;
        using const_vector_completion_f = std::function<void(manager &, const_vector_result_t)>;
        using const_map_completion_f = std::function<void(manager &, const_map_result_t)>;

        manager(std::string const &db_path, model const &model, size_t const priority_count = 1);
        manager(std::nullptr_t);

        void suspend();
        void resume();

        void setup(vector_completion_f completion);

        std::string const &database_path() const;
        database const &database() const;
        db::database &database();
        model const &model() const;
        integer::type current_save_id() const;
        integer::type last_save_id() const;

        void execute(execution_f &&execution, priority_t const priority = 0);

        void insert_objects(insert_prepare_f prepare, vector_completion_f completion, priority_t const priority = 0);
        void fetch_objects(std::string const &entity_name, select_option option, vector_completion_f completion,
                           priority_t const priority = 0);
        void fetch_objects(integer_set_map obj_ids, map_completion_f completion, priority_t const priority = 0);
        void fetch_const_objects(std::string const &entity_name, select_option option,
                                 const_vector_completion_f completion, priority_t const priority = 0);
        void fetch_const_objects(integer_set_map obj_ids, const_map_completion_f completion,
                                 priority_t const priority = 0);
        void save(vector_completion_f completion, priority_t const priority = 0);
        void revert(db::integer::type const save_id, vector_completion_f completion, priority_t const priority = 0);

        object cached_object(std::string const &entity_name, integer::type const object_id) const;

       private:
        void _object_did_change(object const &);
        void _object_did_erase(std::string const &entity_name, integer::type const object_id);
    };
}

std::string to_string(db::manager::error_type const &);
}
