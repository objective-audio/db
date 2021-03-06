//
//  yas_db_attribute.h
//

#pragma once

#include <db/yas_db_value.h>

namespace yas::db {
class attribute_args;

struct attribute final {
    std::string const name;
    std::string const type;
    db::value const default_value;
    bool const not_null;
    bool const primary;
    bool const unique;

    attribute(attribute_args);

    [[nodiscard]] std::string sql() const;

    [[nodiscard]] static db::attribute const &id_attribute();
    [[nodiscard]] static db::attribute const &object_id_attribute();
    [[nodiscard]] static db::attribute const &save_id_attribute();
    [[nodiscard]] static db::attribute const &action_attribute();
};
}  // namespace yas::db
