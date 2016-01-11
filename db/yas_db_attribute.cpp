//
//  yas_db_attribute.cpp
//

#include <sstream>
#include "yas_cf_utils.h"
#include "yas_db_attribute.h"
#include "yas_db_cf_utils.h"

using namespace yas;

namespace yas {
namespace db {
    static auto constexpr type_key = "type";
    static auto constexpr default_key = "default";
    static auto constexpr not_null_key = "not_null";
}
}

db::attribute::attribute(std::string const &name, std::string const &type, value const &default_value,
                         bool const not_null, bool const primary, bool const unique)
    : name(name), type(type), default_value(default_value), not_null(not_null), primary(primary), unique(unique) {
    if (name.size() == 0) {
        throw std::invalid_argument("invalid name");
    }

    if (type != db::integer::name && type != db::real::name && type != db::text::name && type != db::blob::name) {
        throw std::invalid_argument("invalid type");
    }

    if (default_value) {
        auto const &default_type = default_value.type();
        if (type == db::integer::name && default_type != typeid(db::integer)) {
            throw std::invalid_argument("invalid default_value type");
        } else if (type == db::real::name && default_type != typeid(db::real)) {
            throw std::invalid_argument("invalid default_value type");
        } else if (type == db::text::name && default_type != typeid(db::text)) {
            throw std::invalid_argument("invalid default_value type");
        } else if (type == db::blob::name && default_type != typeid(db::blob)) {
            throw std::invalid_argument("invalid default_value type");
        }
    } else if (not_null) {
        throw std::invalid_argument("invalid default_value not null");
    }
}

db::attribute::attribute(std::string const &name, CFDictionaryRef const dict)
    : attribute(name, get<std::string>(dict, type_key), get<value>(dict, default_key), get<bool>(dict, not_null_key),
                false) {
}

std::string db::attribute::sql() const {
    std::ostringstream stream;
    stream << name << " " << type;
    if (primary) {
        stream << " primary key";
    }
    if (unique) {
        stream << " unique";
    }
    if (not_null) {
        stream << " not null";
    }
    if (default_value) {
        stream << " default " << default_value.sql();
    }
    return stream.str();
}

db::attribute db::attribute::id_attribute() {
    return db::attribute{id_field, db::integer::name, nullptr, false, true};
}

db::attribute db::attribute::object_id_attribute() {
    return db::attribute{object_id_field, db::integer::name, db::value{0}, true};
}

db::attribute db::attribute::save_id_attribute() {
    return db::attribute{save_id_field, db::integer::name, db::value{0}, true};
}

db::attribute db::attribute::removed_attribute() {
    return db::attribute{removed_field, db::integer::name, nullptr};
}
