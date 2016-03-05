//
//  yas_db_entity.cpp
//

#include "yas_db_additional_protocol.h"
#include "yas_db_attribute.h"
#include "yas_db_entity.h"
#include "yas_db_relation.h"
#include "yas_db_sql_utils.h"
#include "yas_stl_utils.h"

using namespace yas;

db::entity::entity(std::string const &name, attribute_map &&attributes, relation_map &&relations)
    : name(name), attributes(std::move(attributes)), relations(std::move(relations)) {
}

std::string db::entity::sql_for_create() const {
    auto mapped_attrs = to_vector<std::string>(attributes, [](auto const &pair) { return pair.second.sql(); });
    return db::create_table_sql(name, mapped_attrs);
}

std::string db::entity::sql_for_update() const {
    auto mapped_fields = to_vector<std::string>(attributes, [](auto const &pair) { return pair.first; });
    return db::update_sql(name, mapped_fields, equal_field_expr(id_field));
}

std::string db::entity::sql_for_insert() const {
    std::vector<std::string> mapped_fields;
    for (auto const &pair : attributes) {
        auto const &field_name = pair.first;
        if (field_name != id_field) {
            mapped_fields.push_back(field_name);
        }
    }
    return db::insert_sql(name, mapped_fields);
}