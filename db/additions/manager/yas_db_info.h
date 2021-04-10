//
//  yas_db_info.h
//

#pragma once

#include <cpp_utils/yas_version.h>
#include <db/yas_db_additional_protocol.h>

#include <string>

namespace yas::db {
class value;

struct info final {
    info(std::string version, db::integer::type const current_save_id, db::integer::type const last_save_id);
    explicit info(db::value_map_t values);

    [[nodiscard]] yas::version const &version() const;
    [[nodiscard]] db::integer::type const &current_save_id() const;
    [[nodiscard]] db::integer::type const &last_save_id() const;
    [[nodiscard]] db::integer::type next_save_id() const;

    [[nodiscard]] db::value const &current_save_id_value() const;
    [[nodiscard]] db::value const &last_save_id_value() const;
    [[nodiscard]] db::value next_save_id_value() const;

    [[nodiscard]] static std::string const &sql_for_create();
    [[nodiscard]] static std::string const &sql_for_insert();
    [[nodiscard]] static std::string const &sql_for_update_version();
    [[nodiscard]] static std::string const &sql_for_update_save_ids();
    [[nodiscard]] static std::string const &sql_for_update_current_save_id();

    bool operator==(info const &rhs) const;
    bool operator!=(info const &rhs) const;

   private:
    yas::version _version;
    db::value _current_save_id;
    db::value _last_save_id;
};
}  // namespace yas::db
