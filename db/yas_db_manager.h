//
//  yas_db_manager.h
//

#pragma once

#include "yas_base.h"
#include "yas_db_additional_protocol.h"
#include "yas_db_database.h"
#include "yas_db_object.h"
#include "yas_observing.h"
#include "yas_operation_protocol.h"

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
            purge_failed,
            purge_relation_failed,
            vacuum_failed,

            invalid_version_text,
            version_not_found,
            save_id_not_found,
            out_of_range_save_id,
            last_insert_rowid_failed,
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

        struct change_info {
            db::object const object;

            change_info(std::nullptr_t);
            change_info(db::object const &object);
        };

        static auto constexpr object_change_key = "object_change";
        static auto constexpr db_info_change_key = "db_info_change";

        using result_t = result<std::nullptr_t, error>;
        using vector_result_t = result<object_vector_map, error>;
        using map_result_t = result<object_map_map, error>;
        using const_vector_result_t = result<const_object_vector_map, error>;
        using const_map_result_t = result<const_object_map_map, error>;

        using execution_f = std::function<void(operation const &)>;

        using insert_preparation_count_f = std::function<entity_count_map(void)>;
        using insert_preparation_values_f = std::function<value_map_vector_map(void)>;
        using fetch_preparation_option_f = std::function<select_option(void)>;
        using fetch_preparation_ids_f = std::function<integer_set_map(void)>;
        using revert_preparation_f = std::function<integer::type(void)>;

        using completion_f = std::function<void(result_t)>;
        using vector_completion_f = std::function<void(vector_result_t)>;
        using map_completion_f = std::function<void(map_result_t)>;
        using const_vector_completion_f = std::function<void(const_vector_result_t)>;
        using const_map_completion_f = std::function<void(const_map_result_t)>;

        manager(std::string const &db_path, model const &model, std::size_t const priority_count = 1);
        manager(std::nullptr_t);

        std::string const &database_path() const;
        database const &database() const;
        db::database &database();
        model const &model() const;
        db::value const &current_save_id() const;
        db::value const &last_save_id() const;

        yas::subject<change_info> const &subject() const;
        yas::subject<change_info> &subject();

        db::object insert_object(std::string const entity_name);

        void suspend();
        void resume();

        void execute(execution_f &&execution, operation_option_t &&option = {});

        void setup(completion_f, operation_option_t option = {});
        void clear(completion_f, operation_option_t option = {});
        void purge(completion_f, operation_option_t option = {});
        void reset(completion_f, operation_option_t option = {});
        void insert_objects(insert_preparation_count_f preparation, vector_completion_f completion,
                            operation_option_t option = {});
        void insert_objects(insert_preparation_values_f preparation, vector_completion_f completion,
                            operation_option_t option = {});
        void fetch_objects(fetch_preparation_option_f preparation, vector_completion_f completion,
                           operation_option_t option = {});
        void fetch_objects(fetch_preparation_ids_f preparation, map_completion_f completion,
                           operation_option_t option = {});
        void fetch_const_objects(fetch_preparation_option_f preparation, const_vector_completion_f completion,
                                 operation_option_t option = {});
        void fetch_const_objects(fetch_preparation_ids_f preparation, const_map_completion_f completion,
                                 operation_option_t option = {});
        void save(vector_completion_f completion, operation_option_t option = {});
        void revert(revert_preparation_f preparation, vector_completion_f completion, operation_option_t option = {});

        object cached_object(std::string const &entity_name, integer::type const object_id) const;

        bool has_inserted_objects() const;
        bool has_changed_objects() const;
        std::size_t inserted_object_count(std::string const &entity_name) const;
        std::size_t changed_object_count(std::string const &entity_name) const;

       private:
        void _object_did_change(object const &);
        void _object_did_erase(std::string const &entity_name, integer::type const object_id);
    };
}

std::string to_string(db::manager::error_type const &);
}
