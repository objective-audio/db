//
//  yas_db_object_identifier.h
//

#pragma once

#include "yas_db_value.h"

namespace yas {
namespace db {
    class value;

    class object_identifier : public base {
        class impl;

       public:
        object_identifier(db::value, bool const is_temporary);
        object_identifier(std::nullptr_t);

        void set_stable(db::integer::type const);
        void set_stable(db::value);

        db::value const &stable() const;
        db::value const &temporary() const;

        bool is_stable() const;
        bool is_temporary() const;

        db::object_identifier copy() const;

        std::size_t hash() const;
    };

    db::object_identifier make_stable_id(db::value);
    db::object_identifier make_temporary_id();

    db::object_identifier const &null_id();
}
}

template <>
struct std::hash<yas::db::object_identifier> {
    std::size_t operator()(yas::db::object_identifier const &obj_id) const {
        return obj_id.hash();
    }
};
