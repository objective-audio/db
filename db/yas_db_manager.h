//
//  yas_db_manager.h
//

#pragma once

#include <cpp_utils/yas_task_protocol.h>
#include <dispatch/dispatch.h>
#include "yas_db_additional_protocol.h"
#include "yas_db_fetch_option.h"
#include "yas_db_manager_error.h"
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
    std::string const &database_path() const;
    db::database_ptr const &database() const;
    db::model const &model() const;
    db::value const &current_save_id() const;
    db::value const &last_save_id() const;

    chaining::chain_sync_t<db::info_opt> chain_db_info() const;
    chaining::chain_unsync_t<db::object> chain_db_object() const;

    dispatch_queue_t dispatch_queue() const;

    db::object create_object(std::string const entity_name);

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

    db::object cached_or_created_object(std::string const &entity_name, db::object_id const &object_id) const;

    bool has_created_objects() const;
    bool has_changed_objects() const;
    std::size_t created_object_count(std::string const &entity_name) const;
    std::size_t changed_object_count(std::string const &entity_name) const;

    db::object_vector_t relation_objects(db::object const &, std::string const &rel_name) const;
    db::object relation_object_at(db::object const &, std::string const &rel_name, std::size_t const idx) const;
    db::object make_object(std::string const &entity_name);

    static manager_ptr make_shared(std::string const &db_path, db::model const &model,
                                   std::size_t const priority_count = 1,
                                   dispatch_queue_t const dispatch_queue = dispatch_get_main_queue());

   private:
    class impl;

    std::shared_ptr<impl> _impl;

    manager(std::string const &db_path, db::model const &model, std::size_t const priority_count,
            dispatch_queue_t const dispatch_queue);

    void _prepare(manager_ptr const &);

    manager(manager const &) = delete;
    manager(manager &&) = delete;
    manager &operator=(manager const &) = delete;
    manager &operator=(manager &&) = delete;
};
}  // namespace yas::db
