//
//  yas_db_manager.h
//

#pragma once

#include "yas_base.h"
#include "yas_db_additional_protocol.h"
#include "yas_db_object.h"
#include "yas_operation_protocol.h"
#include "yas_db_manager_error.h"
#include "yas_db_fetch_option.h"
#include <dispatch/dispatch.h>

namespace yas {
class operation;

template <typename T, typename K>
class subject;
template <typename T, typename K>
class observer;

namespace db {
    class select_option;
    class model;
    class error;
    class database;

    using entity_count_map_t = std::unordered_map<std::string, std::size_t>;

    class manager : public base {
       public:
        class impl;

        struct change_info {
            db::object const object;

            change_info(std::nullptr_t);
            change_info(db::object const &object);
        };

        enum class method { object_changed, db_info_changed };

        using cancellation_f = std::function<bool(void)>;
        using execution_f = std::function<void(operation const &)>;

        using insert_preparation_count_f = std::function<db::entity_count_map_t(void)>;
        using insert_preparation_values_f = std::function<db::value_map_vector_map_t(void)>;
        using fetch_preparation_option_f = std::function<db::fetch_option(void)>;
        using fetch_preparation_ids_f = std::function<db::integer_set_map_t(void)>;
        using revert_preparation_f = std::function<db::integer::type(void)>;

        using completion_f = std::function<void(db::manager_result_t)>;
        using vector_completion_f = std::function<void(db::manager_vector_result_t)>;
        using map_completion_f = std::function<void(db::manager_map_result_t)>;
        using const_vector_completion_f = std::function<void(db::manager_const_vector_result_t)>;
        using const_map_completion_f = std::function<void(db::manager_const_map_result_t)>;

        using subject_t = subject<change_info, method>;
        using observer_t = observer<change_info, method>;

        manager(std::string const &db_path, db::model const &model, std::size_t const priority_count = 1,
                dispatch_queue_t const dispatch_queue = dispatch_get_main_queue());
        manager(std::nullptr_t);

        std::string const &database_path() const;
        db::database const &database() const;
        db::database &database();
        db::model const &model() const;
        db::value const &current_save_id() const;
        db::value const &last_save_id() const;

        subject_t const &subject() const;
        subject_t &subject();

        dispatch_queue_t dispatch_queue() const;

        db::object create_object(std::string const entity_name);

        void suspend();
        void resume();
        bool is_suspended() const;

        void execute(execution_f &&execution, operation_option_t &&option = {},
                     cancellation_f &&cancellation = []() { return false; });

        void setup(completion_f, operation_option_t option = {});
        void clear(cancellation_f, completion_f, operation_option_t option = {});
        void purge(cancellation_f, completion_f, operation_option_t option = {});
        void reset(cancellation_f, completion_f, operation_option_t option = {});
        void insert_objects(cancellation_f, insert_preparation_count_f, vector_completion_f,
                            operation_option_t option = {});
        void insert_objects(cancellation_f, insert_preparation_values_f, vector_completion_f,
                            operation_option_t option = {});
        void fetch_objects(cancellation_f, fetch_preparation_option_f, vector_completion_f,
                           operation_option_t option = {});
        void fetch_objects(cancellation_f, fetch_preparation_ids_f, map_completion_f, operation_option_t option = {});
        void fetch_const_objects(cancellation_f, fetch_preparation_option_f, const_vector_completion_f,
                                 operation_option_t option = {});
        void fetch_const_objects(cancellation_f, fetch_preparation_ids_f, const_map_completion_f,
                                 operation_option_t option = {});
        void save(map_completion_f completion, operation_option_t option = {});
        void revert(revert_preparation_f preparation, vector_completion_f completion, operation_option_t option = {});

        db::object cached_or_created_object(std::string const &entity_name, db::object_id const &object_id) const;

        bool has_created_objects() const;
        bool has_changed_objects() const;
        std::size_t created_object_count(std::string const &entity_name) const;
        std::size_t changed_object_count(std::string const &entity_name) const;

        db::object_observable &object_observable();

       private:
        db::object_observable _object_observable = nullptr;
    };
}
}
