//
//  yas_db_relation.cpp
//

#include "yas_db_additional_protocol.h"
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

db::relation::relation(std::string const &entity_name, std::string const &attr_name, CFDictionaryRef const &dict)
    : entity_name(entity_name),
      name(attr_name),
      target_entity_name(get<std::string>(dict, db::target_key)),
      many(get<bool>(dict, db::many_key)),
      table_name("rel_" + entity_name + "_" + this->name) {
}

std::string db::relation::sql_for_create() const {
    auto id_sql = db::attribute::id_attribute().sql();
    auto src_id_sql = db::attribute{db::src_pk_id_field, db::integer::name}.sql();
    auto src_obj_id_sql = db::attribute{db::src_obj_id_field, db::integer::name}.sql();
    auto tgt_obj_id_sql = db::attribute{db::tgt_obj_id_field, db::integer::name}.sql();
    auto save_id_sql = db::attribute{db::save_id_field, db::integer::name}.sql();

    return db::create_table_sql(this->table_name, {std::move(id_sql), std::move(src_id_sql), std::move(src_obj_id_sql),
                                                   std::move(tgt_obj_id_sql), std::move(save_id_sql)});
}

std::string db::relation::sql_for_insert() const {
    return db::insert_sql(this->table_name,
                          {db::src_pk_id_field, db::src_obj_id_field, db::tgt_obj_id_field, db::save_id_field});
}
