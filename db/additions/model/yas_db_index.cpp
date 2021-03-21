//
//  yas_db_index.cpp
//

#include "yas_db_index.h"

#include "yas_db_sql_utils.h"

using namespace yas;
using namespace yas::db;

index::index(index_args args)
    : name(std::move(args.name)), entity(std::move(args.entity)), attributes(std::move(args.attributes)) {
    if (this->name.size() == 0) {
        throw std::invalid_argument("invalid name.");
    }

    if (this->entity.size() == 0) {
        throw std::invalid_argument("invalid empty.");
    }

    if (this->attributes.size() == 0) {
        throw std::invalid_argument("attributes is empty.");
    }

    for (auto const &attribute : this->attributes) {
        if (attribute.size() == 0) {
            throw std::invalid_argument("invalid attribute.");
        }
    }
}

std::string index::sql_for_create() const {
    return create_index_sql(this->name, this->entity, this->attributes);
}
