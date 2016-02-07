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

        using entity_count_map = std::unordered_map<std::string, std::size_t>;

        using state_t = result<std::nullptr_t, error>;
        using result_t = result<object_vector_map, error>;
        using completion_f = std::function<void(manager &, result_t)>;
        using execution_f = std::function<void(manager &, operation const &)>;

        explicit manager(std::string const &db_path, model const &model, size_t const priority_count = 1);
        manager(std::nullptr_t);
        
        void suspend();
        void resume();

        void setup(completion_f completion);

        std::string const &database_path() const;
        database const &database() const;
        db::database &database();
        model const &model() const;
        integer::type current_save_id() const;
        integer::type last_save_id() const;

        void execute(execution_f &&execution, priority_t const priority = 0);

        void insert_objects(entity_count_map const &counts, completion_f completion, priority_t const priority = 0);
        void fetch_objects(std::string const &entity_name, select_option option, completion_f completion,
                           priority_t const priority = 0);
        void fetch_relation_objects(object_vector_map const &objects, completion_f completion,
                                    priority_t const priority = 0);
        void save(completion_f completion, priority_t const priority = 0);
        void revert(db::integer::type const save_id, completion_f completion, priority_t const priority = 0);

        object cached_object(std::string const &entity_name, integer::type const object_id) const;

       private:
        void _object_did_change(object const &);
        void _object_did_erase(std::string const &entity_name, integer::type const object_id);
    };
}

std::string to_string(db::manager::error_type const &);
}
