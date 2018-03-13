//
//  yas_db_index.cpp
//

#include "yas_db_index.h"
#include "yas_db_sql_utils.h"

using namespace yas;

namespace yas::db {
static std::string const entity_key = "entity";
static std::string const attributes_key = "attributes";
}

db::index::index(index_args args)
    : name(std::move(args.name)), entity(std::move(args.entity)), attributes(std::move(args.attributes)) {
}

std::string db::index::sql_for_create() const {
    return create_index_sql(this->name, this->entity, this->attributes);
}
