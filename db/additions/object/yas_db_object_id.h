//
//  yas_db_object_id.h
//

#pragma once

#include <db/yas_db_value.h>

namespace yas::db {
class value;

struct object_id final {
    object_id(db::value stable, db::value temporary);
    object_id(std::nullptr_t);

    [[nodiscard]] uintptr_t identifier() const;

    void set_stable(db::integer::type const);
    void set_stable(db::value);

    [[nodiscard]] db::value const &stable_value() const;
    [[nodiscard]] db::value const &temporary_value() const;
    [[nodiscard]] db::integer::type const &stable() const;
    [[nodiscard]] std::string const &temporary() const;

    [[nodiscard]] bool is_stable() const;
    [[nodiscard]] bool is_temporary() const;

    [[nodiscard]] db::object_id copy() const;

    [[nodiscard]] std::size_t hash() const;

    bool operator==(object_id const &rhs) const;
    bool operator!=(object_id const &rhs) const;

    explicit operator bool() const;

   private:
    class impl;
    std::shared_ptr<impl> _impl;

    bool _is_equal(object_id const &rhs) const;
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
