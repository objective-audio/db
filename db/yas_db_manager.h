//
//  yas_db_manager.h
//

#pragma once

#include <dispatch/dispatch.h>
#include "yas_base.h"
#include "yas_db_additional_protocol.h"
#include "yas_db_fetch_option.h"
#include "yas_db_manager_error.h"
#include "yas_db_object.h"
#include "yas_operation_protocol.h"

namespace yas {
class operation;

template <typename T, typename K>
class subject;
template <typename T, typename K>
class observer;
}  // namespace yas

namespace yas::db {
class select_option;
class model;
class error;
class database;

class manager : public base {
   public:
    class impl;

    manager(std::string const &db_path, db::model const &model, std::size_t const priority_count = 1,
            dispatch_queue_t const dispatch_queue = dispatch_get_main_queue());
    manager(std::nullptr_t);

    std::string const &database_path() const;
    db::database const &database() const;
    db::database &database();
    db::model const &model() const;
    db::value const &current_save_id() const;
    db::value const &last_save_id() const;

    chaining::chain_syncable_t<db::info> chain_db_info() const;
    chaining::chain_unsyncable_t<db::object> chain_db_object() const;

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

    db::object_observable &object_observable();
    db::object make_object(std::string const &entity_name);

   private:
    db::object_observable _object_observable = nullptr;
};
}  // namespace yas::db
