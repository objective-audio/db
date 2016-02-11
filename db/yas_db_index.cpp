//
//  yas_db_index.cpp
//

#include "yas_db_cf_utils.h"
#include "yas_db_index.h"
#include "yas_db_sql_utils.h"
#include "yas_stl_utils.h"

using namespace yas;

namespace yas {
namespace db {
    static std::string const entity_key = "entity";
    static std::string const attributes_key = "attributes";
}
}

db::index::index(std::string const &name, std::string const &table_name, std::vector<std::string> const &attr_names)
    : name(name), table_name(table_name), attribute_names(attr_names) {
}

db::index::index(std::string const &name, CFDictionaryRef const dict)
    : index(name, get<std::string>(dict, entity_key), get<std::vector<std::string>>(dict, attributes_key)) {
}

std::string db::index::sql_for_create() const {
    return create_index_sql(name, table_name, attribute_names);
}