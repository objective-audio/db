//
//  yas_db_identifier.h
//

#pragma once

#include "yas_db_value.h"

namespace yas {
namespace db {
    class value;

    class identifier : public base {
        class impl;

       public:
        identifier(db::value, bool const is_temporary);
        identifier(std::nullptr_t);

        void set_stable(db::integer::type const);
        void set_stable(db::value);

        db::value const &stable() const;
        db::value const &temporary() const;

        bool is_stable() const;
        bool is_temporary() const;
    };

    db::identifier make_stable_id(db::value);
    db::identifier make_temporary_id(db::value);

    db::identifier const &null_id();
}
}
