//
//  yas_db_attribute.cpp
//

#include "yas_db_attribute.h"

#include <sstream>

#include "yas_db_additional_protocol.h"
#include "yas_db_object.h"

using namespace yas;
using namespace yas::db;

namespace yas {
static std::string to_string(attribute_type const &type) {
    switch (type) {
        case attribute_type::integer:
            return db::integer::name;
        case attribute_type::real:
            return db::real::name;
        case attribute_type::text:
            return db::text::name;
        case attribute_type::blob:
            return db::blob::name;
    }
}
}  // namespace yas

attribute::attribute(attribute_args args)
    : name(std::move(args.name)),
      type(to_string(args.type)),
      default_value(std::move(args.default_value)),
      not_null(args.not_null),
      primary(args.primary),
      unique(args.unique) {
    if (this->name.size() == 0) {
        throw std::invalid_argument("invalid name");
    }

    if (this->default_value) {
        std::type_info const &default_type = this->default_value.type();
        if (this->type == db::integer::name && default_type != typeid(db::integer)) {
            throw std::invalid_argument("invalid default_value type");
        } else if (type == db::real::name && default_type != typeid(db::real)) {
            throw std::invalid_argument("invalid default_value type");
        } else if (type == db::text::name && default_type != typeid(db::text)) {
            throw std::invalid_argument("invalid default_value type");
        } else if (type == db::blob::name && default_type != typeid(db::blob)) {
            throw std::invalid_argument("invalid default_value type");
        }
    } else if (this->not_null) {
        throw std::invalid_argument("invalid default_value not null");
    }
}

std::string attribute::sql() const {
    std::ostringstream stream;
    stream << this->name << " " << this->type;
    if (this->primary) {
        stream << " PRIMARY KEY AUTOINCREMENT";
    }
    if (this->unique) {
        stream << " UNIQUE";
    }
    if (this->not_null) {
        stream << " NOT NULL";
    }
    if (this->default_value) {
        stream << " DEFAULT " << this->default_value.sql();
    }
    return stream.str();
}

attribute const &attribute::id_attribute() {
    static attribute const attr{{db::pk_id_field, attribute_type::integer, nullptr, false, true}};
    return attr;
}

attribute const &attribute::object_id_attribute() {
    static attribute const attr{{db::object_id_field, attribute_type::integer, db::value{db::integer::type{0}}, true}};
    return attr;
}

attribute const &attribute::save_id_attribute() {
    static attribute const attr{{db::save_id_field, attribute_type::integer, db::value{db::integer::type{0}}, true}};
    return attr;
}

attribute const &attribute::action_attribute() {
    static attribute const attr{{db::action_field, attribute_type::text, db::insert_action_value(), true}};
    return attr;
}
