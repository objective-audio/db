//
//  yas_db_sample_controller.h
//

#pragma once

namespace yas {
namespace sample {
    class db_controller : public std::enable_shared_from_this<db_controller> {
       public:
        static auto constexpr objects_did_update_key = "objects_did_update";
        static auto constexpr object_did_insert_key = "object_did_insert";
        static auto constexpr object_did_remove_key = "object_did_remove";
        static auto constexpr processing_did_change_key = "processing_did_change";
        static auto constexpr object_did_change_key = "obj_did_change";
        static auto constexpr db_info_did_change_key = "db_info_did_change";

        db_controller();

        void setup(db::manager::completion_f completion);

        void add();
        void remove(std::size_t const &idx);
        void undo();
        void redo();
        void clear();
        void purge();
        void save();
        void cancel();

        bool can_undo() const;
        bool can_redo() const;
        bool can_clear() const;
        bool can_purge() const;
        bool has_changed() const;

        db::object const &object(std::size_t const idx) const;
        std::size_t object_count() const;

        db::integer::type const &current_save_id() const;
        db::integer::type const &last_save_id() const;

        subject<db::value> &subject();

        bool is_processing() const;

       private:
        db::manager _manager;
        db::object_vector _objects;
        yas::subject<db::value> _subject;
        yas::observer<db::manager::change_info> _observer;
        bool _processing;

        void _update_objects(std::function<void(db::manager::result_t)> &&);
        void _begin_processing();
        void _end_processing();
    };
}
}
