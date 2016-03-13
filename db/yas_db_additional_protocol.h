//
//  yas_db_additional_protocol.h
//

#pragma once

#include "yas_db_value.h"
#include "yas_protocol.h"

namespace yas {
namespace db {
    class object;

    // for manager
    static std::string const info_table = "db_info";
    static std::string const version_field = "version";
    static std::string const current_save_id_field = "cur_save_id";
    static std::string const last_save_id_field = "last_save_id";

    // for attribute
    static std::string const id_field = "id";
    static std::string const object_id_field = "obj_id";
    static std::string const save_id_field = "save_id";
    static std::string const action_field = "action";

    static std::string const insert_action = "insert";
    static std::string const update_action = "update";
    static std::string const remove_action = "remove";

    // for relation
    static std::string const src_id_field = "src_id";
    static std::string const src_obj_id_field = "src_obj_id";
    static std::string const tgt_obj_id_field = "tgt_obj_id";

    enum class object_status {
        invalid,
        inserted,
        saved,
        changed,
        updating,
    };

    struct manageable_object : protocol {
        struct impl : protocol::impl {
            virtual void set_status(object_status const &) = 0;
            virtual void load_insertion_data() = 0;
        };

        explicit manageable_object(std::shared_ptr<impl> impl) : protocol(std::move(impl)) {
        }

        void set_status(object_status const &status) {
            impl_ptr<impl>()->set_status(status);
        }

        void load_insertion_data() {
            impl_ptr<impl>()->load_insertion_data();
        }
    };

    struct object_observable : protocol {
        struct impl : protocol::impl {
            virtual void _object_did_change(object const &) = 0;
            virtual void _object_did_erase(std::string const &entity_name, integer::type const object_id) = 0;
        };

        explicit object_observable(std::shared_ptr<impl> impl) : protocol(std::move(impl)) {
        }

        void object_did_change(object const &obj) {
            impl_ptr<impl>()->_object_did_change(obj);
        }

        void object_did_erase(std::string const &entity_name, integer::type const object_id) {
            impl_ptr<impl>()->_object_did_erase(entity_name, object_id);
        }
    };
}
}
