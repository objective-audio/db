//
//  yas_db_attribute.cpp
//

#include "yas_db_attribute.h"

#include <sstream>

#include "yas_db_additional_protocol.h"
#include "yas_db_object.h"

using namespace yas;

namespace yas {
static std::string to_string(db::attribute_type const &type) {
    switch (type) {
        case db::attribute_type::integer:
            return db::integer::name;
        case db::attribute_type::real:
            return db::real::name;
        case db::attribute_type::text:
            return db::text::name;
        case db::attribute_type::blob:
            return db::blob::name;
    }
}
}  // namespace yas

db::attribute::attribute(attribute_args args)
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

std::string db::attribute::sql() const {
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

db::attribute const &db::attribute::id_attribute() {
    static db::attribute const attr{{db::pk_id_field, db::attribute_type::integer, nullptr, false, true}};
    return attr;
}

db::attribute const &db::attribute::object_id_attribute() {
    static db::attribute const attr{
        {db::object_id_field, db::attribute_type::integer, db::value{db::integer::type{0}}, true}};
    return attr;
}

db::attribute const &db::attribute::save_id_attribute() {
    static db::attribute const attr{
        {db::save_id_field, db::attribute_type::integer, db::value{db::integer::type{0}}, true}};
    return attr;
}

db::attribute const &db::attribute::action_attribute() {
    static db::attribute const attr{{db::action_field, db::attribute_type::text, db::insert_action_value(), true}};
    return attr;
}
