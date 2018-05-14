//
//  yas_db_info.h
//

#pragma once

#include <string>
#include "yas_base.h"
#include "yas_db_additional_protocol.h"

namespace yas {
class version;
}

namespace yas::db {
class value;

class info : public base {
    class impl;

   public:
    info(std::string version, db::integer::type const current_save_id, db::integer::type const last_save_id);
    explicit info(db::value_map_t values);
    info(std::nullptr_t);

    yas::version const &version() const;
    db::integer::type const &current_save_id() const;
    db::integer::type const &last_save_id() const;
    db::integer::type next_save_id() const;

    db::value const &current_save_id_value() const;
    db::value const &last_save_id_value() const;
    db::value next_save_id_value() const;

    static std::string const &sql_for_create();
    static std::string const &sql_for_insert();
    static std::string const &sql_for_update_version();
    static std::string const &sql_for_update_save_ids();
    static std::string const &sql_for_update_current_save_id();
};

db::info const &null_info();
}  // namespace yas::db
