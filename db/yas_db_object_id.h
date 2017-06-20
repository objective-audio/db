//
//  yas_db_object_id.h
//

#pragma once

#include "yas_db_value.h"

namespace yas {
namespace db {
    class value;

    class object_id : public base {
        class impl;

       public:
        object_id(db::value stable, db::value temporary);
        object_id(std::nullptr_t);

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
    };

    db::object_id make_stable_id(db::value);
    db::object_id make_stable_id(db::integer::type const);
    db::object_id make_temporary_id();

    db::object_id const &null_id();
}
std::string to_string(db::object_id const &);
}

template <>
struct std::hash<yas::db::object_id> {
    std::size_t operator()(yas::db::object_id const &obj_id) const {
        return obj_id.hash();
    }
};
