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
        enum class method { objects_updated, object_inserted, processing_changed, object_changed, db_info_changed };

        struct change_info {
            db::object const object;
            db::value const value;

            change_info(std::nullptr_t);
            change_info(db::object object, db::value value);
        };

        using subject_t = subject<change_info, method>;
        using observer_t = observer<change_info, method>;

        db_controller();

        void setup(db::manager::completion_f completion);

        void add_temporary(entity const &);
        void add(entity const &);
        void remove(entity const &, std::size_t const &idx);
        void undo();
        void redo();
        void clear();
        void purge();
        void save_changed();
        void cancel_changed();

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
        void _update_objects(std::function<void(db::manager::result_t)> &&);
        void _update_objects(entity const &entity, std::function<void(db::manager::result_t)> &&);
        void _begin_processing();
        void _end_processing();
    };
}
}
