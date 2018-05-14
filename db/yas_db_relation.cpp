//
//  yas_db_relation.cpp
//

#include "yas_db_relation.h"
#include "yas_db_attribute.h"
#include "yas_db_sql_utils.h"

using namespace yas;

db::relation::relation(relation_args args, std::string source)
    : name(std::move(args.name)),
      source(std::move(source)),
      target(std::move(args.target)),
      many(args.many),
      table("rel_" + this->source + "_" + this->name) {
    if (this->name.size() == 0) {
        throw std::invalid_argument("invalid name");
    }
}

std::string db::relation::sql_for_create() const {
    std::string id_sql = db::attribute::id_attribute().sql();
    std::string src_pk_id_sql = db::attribute{{db::src_pk_id_field, db::attribute_type::integer}}.sql();
    std::string src_obj_id_sql = db::attribute{{db::src_obj_id_field, db::attribute_type::integer}}.sql();
    std::string tgt_obj_id_sql = db::attribute{{db::tgt_obj_id_field, db::attribute_type::integer}}.sql();
    std::string save_id_sql = db::attribute{{db::save_id_field, db::attribute_type::integer}}.sql();

    return db::create_table_sql(this->table, {std::move(id_sql), std::move(src_pk_id_sql), std::move(src_obj_id_sql),
                                              std::move(tgt_obj_id_sql), std::move(save_id_sql)});
}

std::string db::relation::sql_for_insert() const {
    return db::insert_sql(this->table,
                          {db::src_pk_id_field, db::src_obj_id_field, db::tgt_obj_id_field, db::save_id_field});
}
