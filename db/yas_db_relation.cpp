//
//  yas_db_relation.cpp
//

#include "yas_db_attribute.h"
#include "yas_db_cf_utils.h"
#include "yas_db_entity.h"
#include "yas_db_relation.h"
#include "yas_db_sql_utils.h"
#include "yas_stl_utils.h"

using namespace yas;

namespace yas {
namespace db {
    static auto constexpr target_key = "target";
    static auto constexpr many_key = "many";
    static auto constexpr cascade = "cascade";
}
}

db::relation::relation(std::string const entity_name, std::string const &attribute_name, CFDictionaryRef const &dict)
    : entity_name(entity_name),
      name(attribute_name),
      target_entity_name(get<std::string>(dict, target_key)),
      many(get<bool>(dict, many_key)),
      table_name("rel_" + entity_name + "_" + name) {
}

std::string db::relation::sql() const {
    auto id_sql = db::attribute::id_attribute().sql();
    auto src_id_sql = db::attribute{src_id_field, db::integer::name}.sql();
    auto tgt_id_sql = db::attribute{tgt_id_field, db::integer::name}.sql();
    auto src_foreign_sql = db::foreign_key(src_id_field, entity_name, db::id_field, cascade, cascade);
    auto tgt_foreign_sql = db::foreign_key(tgt_id_field, target_entity_name, db::id_field, cascade, cascade);

    return db::create_table_sql(table_name, {std::move(id_sql), std::move(src_id_sql), std::move(tgt_id_sql),
                                             std::move(src_foreign_sql), std::move(tgt_foreign_sql)});
}
