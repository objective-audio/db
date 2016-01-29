//
//  yas_db_manager.h
//

#pragma once

#include "yas_base.h"
#include "yas_db_database.h"
#include "yas_db_object.h"

namespace yas {
class operation;

namespace db {
    class select_option;
    class model;
    class error;

    static std::string const info_table = "db_info";
    static std::string const version_field = "version";
    static std::string const current_save_id_field = "cur_save_id";
    static std::string const last_save_id_field = "last_save_id";

    class manager : public base, public object_observable {
        using super_class = base;

       public:
        class impl;

        enum class setup_error_type {
            none,
            begin_transaction_failed,
            select_info_failed,
            update_info_failed,
            version_not_found,
            invalid_version_text,
            alter_entity_table_failed,
            create_info_table_failed,
            insert_info_failed,
            create_entity_table_failed,
            create_relation_table_failed
        };

        enum class insert_error_type {
            none,
            insert_failed,
            select_info_failed,
            select_failed,
            update_info_failed,
            save_id_not_found,
            update_save_id_failed
        };

        enum class save_error_type { none, save_id_not_found, update_save_id_failed, insert_failed, delete_failed };

        enum class fetch_error_type { none, begin_transaction_failed, select_failed, save_id_not_found };

        enum class revert_error_type {
            none,
            begin_transaction_failed,
            select_failed,
            save_id_not_found,
            out_of_range_save_id,
            update_save_id_failed
        };

        template <typename T>
        struct error {
            error(std::nullptr_t);
            explicit error(T const &error_type, db::error const &db_error = nullptr);

            explicit operator bool() const;

            T const &type() const;
            db::error const &database_error() const;

           private:
            T _type;
            db::error _db_error;
        };

        using entity_count_map = std::unordered_map<std::string, std::size_t>;

        using setup_result = result<std::nullptr_t, error<setup_error_type>>;
        using insert_result = result<object_vector_map, error<insert_error_type>>;
        using fetch_result = result<object_vector_map, error<fetch_error_type>>;
        using save_result = result<object_vector_map, error<save_error_type>>;
        using revert_result = result<object_vector_map, error<revert_error_type>>;

        using setup_completion_f = std::function<void(manager &, setup_result const &)>;
        using insert_completion_f = std::function<void(manager &, insert_result const &)>;
        using fetch_completion_f = std::function<void(manager &, fetch_result const &)>;
        using save_completion_f = std::function<void(manager &, save_result const &)>;
        using revert_completion_f = std::function<void(manager &, revert_result const &)>;
        using execution_f = std::function<void(manager &, operation const &)>;

        explicit manager(std::string const &db_path, model const &model);
        manager(std::nullptr_t);

        void setup(setup_completion_f &&completion);

        std::string const &database_path() const;
        database const &database() const;
        db::database &database();
        model const &model() const;
        integer::type current_save_id() const;
        integer::type last_save_id() const;

        void execute(execution_f &&execution);

        void insert_objects(entity_count_map const &counts, insert_completion_f &&completion);
        void fetch_objects(std::string const &entity_name, select_option &&option, fetch_completion_f &&completion);
        void fetch_relation_objects(object_vector_map const &objects, fetch_completion_f &&completion);
        void save(save_completion_f &&completion);
        void revert(db::integer::type const save_id, revert_completion_f &&completion);

        object cached_object(std::string const &entity_name, integer::type const object_id) const;

       private:
        void _object_did_change(object const &);
        void _object_did_erase(std::string const &entity_name, integer::type const object_id);
    };
}

std::string to_string(db::manager::setup_error_type const &);
std::string to_string(db::manager::insert_error_type const &);
std::string to_string(db::manager::save_error_type const &);
std::string to_string(db::manager::fetch_error_type const &);
std::string to_string(db::manager::revert_error_type const &);

template <typename T>
db::manager::error<T> make_error(T const &error_type, db::error const &error = nullptr) {
    return db::manager::error<T>{error_type, error};
}
}
