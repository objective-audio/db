//
//  yas_db_info.h
//

#pragma once

#include "yas_base.h"
#include "yas_db_additional_protocol.h"
#include <string>

namespace yas {
namespace db {
    class value;

    class info : public base {
        class impl;

       public:
        info(std::string version, db::integer::type const current_save_id, db::integer::type const last_save_id);
        explicit info(db::value_map_t values);
        info(std::nullptr_t);

        std::string const &version() const;
        db::integer::type const &current_save_id() const;
        db::integer::type const &last_save_id() const;

        db::value const &version_value() const;
        db::value const &current_save_id_value() const;
        db::value const &last_save_id_value() const;
    };

    db::info const &null_info();
}
}
