//
//  yas_db_info.h
//

#pragma once

#include <cpp_utils/yas_version.h>
#include <string>
#include "yas_db_additional_protocol.h"

namespace yas::db {
class value;

struct info final {
    info(std::string version, db::integer::type const current_save_id, db::integer::type const last_save_id);
    explicit info(db::value_map_t values);

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

    bool operator==(info const &rhs) const;
    bool operator!=(info const &rhs) const;

   private:
    yas::version _version;
    db::value _current_save_id;
    db::value _last_save_id;
};
}  // namespace yas::db
