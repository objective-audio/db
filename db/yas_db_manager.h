//
//  yas_db_manager.h
//

#pragma once

#include <chaining/yas_chaining_umbrella.h>
#include <cpp_utils/yas_task.h>
#include <cpp_utils/yas_task_protocol.h>
#include <dispatch/dispatch.h>

#include "yas_db_additional_protocol.h"
#include "yas_db_fetch_option.h"
#include "yas_db_manager_error.h"
#include "yas_db_model.h"
#include "yas_db_object.h"
#include "yas_db_ptr.h"

namespace yas {
class task;
}  // namespace yas

namespace yas::db {
class select_option;
class model;
class error;
class database;

struct manager final {
    ~manager();

    std::string const &database_path() const;
    db::database_ptr const &database() const;
    db::model const &model() const;
    db::value const &current_save_id() const;
    db::value const &last_save_id() const;

    chaining::chain_sync_t<db::info_opt> chain_db_info() const;
    chaining::chain_unsync_t<db::object_ptr> chain_db_object() const;

    dispatch_queue_t dispatch_queue() const;

    db::object_ptr create_object(std::string const entity_name);

    void suspend();
    void resume();
    bool is_suspended() const;

    void execute(db::cancellation_f, db::execution_f &&);

    void setup(db::completion_f);
    void clear(db::cancellation_f, db::completion_f);
    void purge(db::cancellation_f, db::completion_f);
    void reset(db::cancellation_f, db::completion_f);
    void insert_objects(db::cancellation_f, db::insert_count_preparation_f, db::vector_completion_f);
    void insert_objects(db::cancellation_f, db::insert_values_preparation_f, db::vector_completion_f);
    void fetch_objects(db::cancellation_f, db::fetch_option_preparation_f, db::vector_completion_f);
    void fetch_objects(db::cancellation_f, db::fetch_ids_preparation_f, db::map_completion_f);
    void fetch_const_objects(db::cancellation_f, db::fetch_option_preparation_f, db::const_vector_completion_f);
    void fetch_const_objects(db::cancellation_f, db::fetch_ids_preparation_f, db::const_map_completion_f);
    void save(db::cancellation_f, db::map_completion_f);
    void revert(db::cancellation_f, db::revert_preparation_f, db::vector_completion_f);

    std::optional<db::object_ptr> cached_or_created_object(std::string const &entity_name,
                                                           db::object_id const &object_id) const;

    bool has_created_objects() const;
    bool has_changed_objects() const;
    std::size_t created_object_count(std::string const &entity_name) const;
    std::size_t changed_object_count(std::string const &entity_name) const;

    db::object_opt_vector_t relation_objects(db::object_ptr const &, std::string const &rel_name) const;
    std::optional<db::object_ptr> relation_object_at(db::object_ptr const &, std::string const &rel_name,
                                                     std::size_t const idx) const;
    db::object_ptr make_object(std::string const &entity_name);

    static manager_ptr make_shared(std::string const &db_path, db::model const &model,
                                   std::size_t const priority_count = 1,
                                   dispatch_queue_t const dispatch_queue = dispatch_get_main_queue());

   private:
    db::manager_wptr _weak_manager;
    db::database_ptr _database;
    db::model _model;
    task_queue _task_queue;
    std::size_t _suspend_count = 0;
    mutable db::weak_pool<db::object_id, db::object> _cached_objects;
    db::tmp_object_map_map_t _created_objects;
    db::object_map_map_t _changed_objects;
    chaining::value::holder_ptr<db::info_opt> _db_info;
    chaining::notifier_ptr<db::object_ptr> _db_object_notifier;
    dispatch_queue_t _dispatch_queue;
    chaining::observer_pool _pool;

    manager(std::string const &db_path, db::model const &model, std::size_t const priority_count,
            dispatch_queue_t const dispatch_queue);

    void _prepare(manager_ptr const &);

    manager(manager const &) = delete;
    manager(manager &&) = delete;
    manager &operator=(manager const &) = delete;
    manager &operator=(manager &&) = delete;

    db::object_ptr _load_and_cache_object(std::string const &entity_name, db::object_data const &data, bool const force,
                                          bool const is_save);
    db::object_vector_map_t _load_and_cache_object_vector(db::object_data_vector_map_t const &datas, bool const force,
                                                          bool const is_save);
    db::object_map_map_t _load_and_cache_object_map(db::object_data_vector_map_t const &datas, bool const force,
                                                    bool const is_save);
    void _clear_cached_objects();
    void _purge_cached_objects();
    void _set_db_info(db::info_opt &&);
    db::object_data_vector_map_t _changed_datas_for_save();
    db::integer_set_map_t _changed_object_ids_for_reset();
    void _erase_changed_objects(db::object_data_vector_map_t const &);
    std::optional<db::object_ptr> _inserted_object(std::string const &entity_name, std::string const &tmp_obj_id) const;
    void _execute(db::cancellation_f &&, db::execution_f &&);
    void _execute_fetch_object_datas(
        db::cancellation_f &&, db::fetch_option_preparation_f &&,
        std::function<void(db::manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas)> &&);
    void _execute_fetch_object_datas(db::cancellation_f &&, fetch_ids_preparation_f &&,
                                     std::function<void(db::manager_result_t &&, db::object_data_vector_map_t &&)> &&);
    void _object_did_change(db::object_ptr const &);
};
}  // namespace yas::db
