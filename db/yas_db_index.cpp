//
//  yas_db_index.cpp
//

#include "yas_db_cf_utils.h"
#include "yas_db_index.h"
#include "yas_db_sql_utils.h"
#include "yas_stl_utils.h"
#include "yas_db_additional_types.h"

using namespace yas;

namespace yas::db {
static std::string const entity_key = "entity";
static std::string const attributes_key = "attributes";
}

db::index::index(index_args args)
    : name(std::move(args.name)), entity(std::move(args.table_name)), attributes(std::move(args.attribute_names)) {
}

db::index::index(std::string const &name, CFDictionaryRef const dict)
    : index(index_args{name, get<std::string>(dict, db::entity_key),
                       get<std::vector<std::string>>(dict, db::attributes_key)}) {
}

std::string db::index::sql_for_create() const {
    return create_index_sql(this->name, this->entity, this->attributes);
}
