//
//  yas_db_additional_protocol.h
//

#pragma once

#include "yas_db_additional_types.h"
#include "yas_protocol.h"
#include "yas_result.h"

namespace yas {
namespace db {
    struct manageable_object : protocol {
        struct impl : protocol::impl {
            virtual void set_status(db::object_status const &) = 0;
            virtual void load_insertion_data() = 0;
            virtual void load_data(db::object_data const &obj_data, bool const force) = 0;
            virtual void load_save_id(db::value const &save_id) = 0;
            virtual void clear_data() = 0;
        };

        explicit manageable_object(std::shared_ptr<impl> impl) : protocol(std::move(impl)) {
        }

        manageable_object(std::nullptr_t) : protocol(nullptr) {
        }

        void set_status(db::object_status const &status) {
            impl_ptr<impl>()->set_status(status);
        }

        void load_insertion_data() {
            impl_ptr<impl>()->load_insertion_data();
        }

        void load_data(db::object_data const &obj_data, bool const force = false) {
            impl_ptr<impl>()->load_data(obj_data, force);
        }

        void load_save_id(db::value const &save_id) {
            impl_ptr<impl>()->load_save_id(save_id);
        }

        void clear_data() {
            impl_ptr<impl>()->clear_data();
        }
    };

    struct object_observable : protocol {
        struct impl : protocol::impl {
            virtual void _object_did_change(object const &) = 0;
            virtual void _object_did_erase(std::string const &entity_name, integer::type const object_id) = 0;
        };

        explicit object_observable(std::shared_ptr<impl> impl) : protocol(std::move(impl)) {
        }

        object_observable(std::nullptr_t) : protocol(nullptr) {
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
