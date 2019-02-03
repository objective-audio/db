//
//  yas_sample_db_controller.h
//

#pragma once

#include <db/yas_db_umbrella.h>

namespace yas::sample {
class db_controller : public std::enable_shared_from_this<db_controller> {
   public:
    enum class entity { a, b };
    enum class method {
        all_objects_updated,
        object_created,
        processing_changed,
        object_changed,
        object_removed,
        db_info_changed
    };

    struct change_info {
        db::object const object;
        db::value const value;

        change_info(std::nullptr_t);
        change_info(db::object object, db::value value);
    };

    using chain_pair_t = std::pair<method, change_info>;

    db_controller();

    void setup(db::completion_f);

    void create_object(entity const &);
    void insert(entity const &, db::completion_f);
    void remove(entity const &, std::size_t const &idx);
    void undo(db::completion_f);
    void redo(db::completion_f);
    void clear(db::completion_f);
    void purge(db::completion_f);
    void save_changed(db::completion_f);
    void cancel_changed(db::completion_f);

    bool can_insert() const;
    bool can_undo() const;
    bool can_redo() const;
    bool can_clear() const;
    bool can_purge() const;
    bool has_changed() const;

    db::object const &object(entity const &, std::size_t const idx) const;
    std::size_t object_count(entity const &) const;

    db::object relation_object_at(db::object const &, std::string const &rel_name, std::size_t const idx) const;

    db::integer::type const &current_save_id() const;
    db::integer::type const &last_save_id() const;

    chaining::chain_unsync_t<chain_pair_t> chain();

    bool is_processing() const;

    static entity entity_for_name(std::string const &);

   private:
    db::manager _manager;
    db::object_vector_map_t _objects;
    chaining::notifier<chain_pair_t> _notifier;
    chaining::observer_pool _pool;
    bool _processing;

    db::object_vector_t &_objects_at(entity const &);
    void _update_objects(std::shared_ptr<db::manager_result_t>, std::function<void(db::manager_result_t)> &&);
    void _update_objects(std::shared_ptr<db::manager_result_t>, entity const &entity);
    void _begin_processing();
    void _end_processing();
};
}  // namespace yas::sample

namespace yas {
std::string to_entity_name(sample::db_controller::entity const &);
}