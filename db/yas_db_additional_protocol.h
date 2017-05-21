//
//  yas_db_additional_protocol.h
//

#pragma once

#include "yas_db_value.h"
#include "yas_protocol.h"
#include "yas_result.h"
#include <set>
#include <unordered_set>
#include <deque>

namespace yas {
namespace db {
    class object;
    class const_object;
    class attribute;
    class relation;
    class object_data;
    class error;
    class entity;
    class index;

    // for object
    using integer_set_t = std::set<db::integer::type>;
    using integer_set_map_t = std::unordered_map<std::string, db::integer_set_t>;

    using object_map_t = std::unordered_map<db::integer::type, object>;
    using object_map_map_t = std::unordered_map<std::string, db::object_map_t>;
    using object_vector_t = std::vector<db::object>;
    using object_vector_map_t = std::unordered_map<std::string, db::object_vector_t>;
    using object_deque_t = std::deque<db::object>;
    using object_deque_map_t = std::unordered_map<std::string, db::object_deque_t>;
    using const_object_map_t = std::unordered_map<db::integer::type, db::const_object>;
    using const_object_map_map_t = std::unordered_map<std::string, db::const_object_map_t>;
    using const_object_vector_t = std::vector<db::const_object>;
    using const_object_vector_map_t = std::unordered_map<std::string, db::const_object_vector_t>;
    using weak_object_map_t = std::unordered_map<db::integer::type, weak<db::object>>;
    using weak_object_map_map_t = std::unordered_map<std::string, db::weak_object_map_t>;
    using object_data_vector_t = std::vector<db::object_data>;
    using object_data_vector_map_t = std::unordered_map<std::string, db::object_data_vector_t>;

    // for model
    using entity_map_t = std::unordered_map<std::string, db::entity>;
    using index_map_t = std::unordered_map<std::string, db::index>;

    // for info
    static std::string const info_table = "db_info";
    static std::string const version_field = "version";
    static std::string const current_save_id_field = "cur_save_id";
    static std::string const last_save_id_field = "last_save_id";

    // for manager
    using object_data_result_t = result<db::object_data, db::error>;
    using object_data_vector_result_t = result<db::object_data_vector_t, db::error>;
    using value_vector_result_t = result<std::vector<db::value>, db::error>;
    using value_vector_map_result_t = result<db::value_vector_map_t, db::error>;

    // for entity
    using attribute_map_t = std::unordered_map<std::string, attribute>;
    using relation_map_t = std::unordered_map<std::string, relation>;
    using string_set_t = std::unordered_set<std::string>;
    using string_set_map_t = std::unordered_map<std::string, string_set_t>;

    // for attribute
    static std::string const pk_id_field = "pk_id";
    static std::string const object_id_field = "obj_id";
    static std::string const save_id_field = "save_id";
    static std::string const action_field = "action";

    static std::string const insert_action = "insert";
    static std::string const update_action = "update";
    static std::string const remove_action = "remove";

    // for relation
    static std::string const src_pk_id_field = "src_pk_id";
    static std::string const src_obj_id_field = "src_obj_id";
    static std::string const tgt_obj_id_field = "tgt_obj_id";

    enum class object_status {
        invalid,
        inserted,
        saved,
        changed,
        updating,
    };

    struct object_data {
        value_map_t attributes;
        value_vector_map_t relations;
    };

    struct manageable_object : protocol {
        struct impl : protocol::impl {
            virtual void set_status(object_status const &) = 0;
            virtual void load_insertion_data() = 0;
            virtual void load_data(object_data const &obj_data, bool const force) = 0;
            virtual void load_save_id(db::value const &save_id) = 0;
            virtual void clear_data() = 0;
        };

        explicit manageable_object(std::shared_ptr<impl> impl) : protocol(std::move(impl)) {
        }

        manageable_object(std::nullptr_t) : protocol(nullptr) {
        }

        void set_status(object_status const &status) {
            impl_ptr<impl>()->set_status(status);
        }

        void load_insertion_data() {
            impl_ptr<impl>()->load_insertion_data();
        }

        void load_data(object_data const &obj_data, bool const force = false) {
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
