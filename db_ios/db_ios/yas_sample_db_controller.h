//
//  yas_sample_db_controller.h
//

#pragma once

#include "yas_db.h"

namespace yas {
namespace sample {
    class db_controller : public std::enable_shared_from_this<db_controller> {
       public:
        enum class entity { a, b };
        enum class method { objects_updated, object_created, processing_changed, object_changed, db_info_changed };

        struct change_info {
            db::object const object;
            db::value const value;

            change_info(std::nullptr_t);
            change_info(db::object object, db::value value);
        };

        using subject_t = subject<change_info, method>;
        using observer_t = observer<change_info, method>;

        db_controller();

        void setup(db::manager::completion_f);

        void create_object(entity const &);
        void insert(entity const &, db::manager::completion_f);
        void remove(entity const &, std::size_t const &idx);
        void undo(db::manager::completion_f);
        void redo(db::manager::completion_f);
        void clear(db::manager::completion_f);
        void purge(db::manager::completion_f);
        void save_changed(db::manager::completion_f);
        void cancel_changed(db::manager::completion_f);

        bool can_add() const;
        bool can_undo() const;
        bool can_redo() const;
        bool can_clear() const;
        bool can_purge() const;
        bool has_changed() const;

        db::object const &object(entity const &, std::size_t const idx) const;
        std::size_t object_count(entity const &) const;

        db::integer::type const &current_save_id() const;
        db::integer::type const &last_save_id() const;

        subject_t &subject();

        bool is_processing() const;

        static entity entity_for_name(std::string const &);

       private:
        db::manager _manager;
        db::object_vector_map_t _objects;
        subject_t _subject;
        yas::db::manager::observer_t _observer;
        bool _processing;

        db::object_vector_t &_objects_at(entity const &);
        void _update_objects(std::shared_ptr<db::manager_result_t>, std::function<void(db::manager_result_t)> &&);
        void _update_objects(std::shared_ptr<db::manager_result_t>, entity const &entity);
        void _begin_processing();
        void _end_processing();
    };
}

std::string to_entity_name(sample::db_controller::entity const &);
}
