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
    static std::string const target_key = "target";
    static std::string const many_key = "many";
}
}

db::relation::relation(std::string const entity_name, std::string const &attribute_name, CFDictionaryRef const &dict)
    : entity_name(entity_name),
      name(attribute_name),
      target_entity_name(get<std::string>(dict, target_key)),
      many(get<bool>(dict, many_key)),
      table_name("rel_" + entity_name + "_" + name) {
}

std::string db::relation::sql_for_create() const {
    auto id_sql = db::attribute::id_attribute().sql();
    auto src_id_sql = db::attribute{src_id_field, db::integer::name}.sql();
    auto src_obj_id_sql = db::attribute{src_obj_id_field, db::integer::name}.sql();
    auto tgt_obj_id_sql = db::attribute{tgt_obj_id_field, db::integer::name}.sql();
    auto save_id_sql = db::attribute{save_id_field, db::integer::name}.sql();

    return db::create_table_sql(table_name, {std::move(id_sql), std::move(src_id_sql), std::move(src_obj_id_sql),
                                             std::move(tgt_obj_id_sql), std::move(save_id_sql)});
}

std::string db::relation::sql_for_insert() const {
    return db::insert_sql(table_name, {src_id_field, src_obj_id_field, tgt_obj_id_field, save_id_field});
}
