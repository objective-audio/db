//
//  yas_db_entity.cpp
//

#include "yas_db_entity.h"
#include "yas_db_sql_utils.h"
#include "yas_stl_utils.h"

using namespace yas;

db::entity::entity(std::string const &name, attributes_map &&attributes, relations_map &&relations)
    : name(name), attributes(std::move(attributes)), relations(std::move(relations)) {
}

std::string db::entity::sql_for_create() const {
    auto mapped_attrs = map<std::string>(attributes, [](auto const &pair) { return pair.second.sql(); });
    return db::create_table_sql(name, mapped_attrs);
}

std::string db::entity::sql_for_update() const {
    auto mapped_fields = map<std::string>(attributes, [](auto const &pair) { return pair.first; });
    return db::update_sql(name, mapped_fields, field_expr(id_field, "="));
}