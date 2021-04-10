//
//  yas_db_manager.h
//

#pragma once

#include <cpp_utils/yas_task.h>
#include <cpp_utils/yas_task_protocol.h>
#include <db/yas_db_additional_protocol.h>
#include <db/yas_db_fetch_option.h>
#include <db/yas_db_manager_error.h>
#include <db/yas_db_model.h>
#include <db/yas_db_object.h>
#include <db/yas_db_ptr.h>

namespace yas {
class task;
}  // namespace yas

namespace yas::db {
class select_option;
class model;
class error;
class database;

struct manager final {
    [[nodiscard]] std::string const &database_path() const;
    [[nodiscard]] db::database_ptr const &database() const;
    [[nodiscard]] db::model const &model() const;
    [[nodiscard]] db::value const &current_save_id() const;
    [[nodiscard]] db::value const &last_save_id() const;

    using db_info_observing_handler_f = std::function<void(info_opt const &)>;
    observing::syncable observe_db_info(db_info_observing_handler_f &&);
    using db_object_observing_handler_f = std::function<void(object_ptr const &)>;
    observing::endable observe_db_object(db_object_observing_handler_f &&);

    db::object_ptr create_object(std::string const entity_name);

    void suspend();
    void resume();
    [[nodiscard]] bool is_suspended() const;

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

    [[nodiscard]] std::optional<db::object_ptr> cached_or_created_object(std::string const &entity_name,
                                                                         db::object_id const &object_id) const;

    [[nodiscard]] bool has_created_objects() const;
    [[nodiscard]] bool has_changed_objects() const;
    [[nodiscard]] std::size_t created_object_count(std::string const &entity_name) const;
    [[nodiscard]] std::size_t changed_object_count(std::string const &entity_name) const;

    [[nodiscard]] db::object_opt_vector_t relation_objects(db::object_ptr const &, std::string const &rel_name) const;
    [[nodiscard]] std::optional<db::object_ptr> relation_object_at(db::object_ptr const &, std::string const &rel_name,
                                                                   std::size_t const idx) const;
    [[nodiscard]] db::object_ptr make_object(std::string const &entity_name);

    [[nodiscard]] static manager_ptr make_shared(std::string const &db_path, db::model const &model,
                                                 std::size_t const priority_count = 1);

   private:
    db::manager_wptr _weak_manager;
    db::database_ptr _database;
    db::model _model;
    task_queue _task_queue;
    std::size_t _suspend_count = 0;
    mutable db::weak_pool<db::object_id, db::object> _cached_objects;
    db::tmp_object_map_map_t _created_objects;
    db::object_map_map_t _changed_objects;
    observing::value::holder_ptr<db::info_opt> const _db_info;
    observing::notifier_ptr<db::object_ptr> const _db_object_notifier;
    observing::canceller_pool _pool;

    manager(std::string const &db_path, db::model const &model, std::size_t const priority_count);

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
