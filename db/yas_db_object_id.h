//
//  yas_db_object_id.h
//

#pragma once

#include <cpp_utils/yas_weakable.h>
#include "yas_db_value.h"

namespace yas::db {
class value;

struct object_id final : weakable<object_id> {
    class impl;

    object_id(db::value stable, db::value temporary);
    object_id(std::shared_ptr<weakable_impl> &&);
    object_id(std::nullptr_t);

    uintptr_t identifier() const;

    void set_stable(db::integer::type const);
    void set_stable(db::value);

    db::value const &stable_value() const;
    db::value const &temporary_value() const;
    db::integer::type const &stable() const;
    std::string const &temporary() const;

    bool is_stable() const;
    bool is_temporary() const;

    db::object_id copy() const;

    std::size_t hash() const;

    std::shared_ptr<weakable_impl> weakable_impl_ptr() const override;

    bool operator==(object_id const &rhs) const;
    bool operator!=(object_id const &rhs) const;

    explicit operator bool() const;

   private:
    std::shared_ptr<impl> _impl;
};

db::object_id make_stable_id(db::value);
db::object_id make_stable_id(db::integer::type const);
db::object_id make_temporary_id();

db::object_id const &null_id();

struct object_id_pool {
    using value_create_handler = std::function<object_id(void)>;

    object_id get_or_create(std::string const &entity_name, object_id const &key, value_create_handler handler);

   private:
    using value_map_t = std::unordered_map<object_id, object_id>;
    std::unordered_map<std::string, value_map_t> _all_values;
};
}  // namespace yas::db

namespace yas {
std::string to_string(db::object_id const &);
}

template <>
struct std::hash<yas::db::object_id> {
    std::size_t operator()(yas::db::object_id const &obj_id) const {
        return obj_id.hash();
    }
};
