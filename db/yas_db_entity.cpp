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

db::entity::entity(std::string const &name, db::attribute_map_t &&attributes, db::relation_map_t &&relations)
    : name(name),
      attributes(std::move(attributes)),
      custom_attributes(filter(this->attributes,
                               [](auto const &pair) {
                                   auto const &attr_name = pair.first;
                                   if (attr_name == db::id_field || attr_name == db::object_id_field ||
                                       attr_name == db::save_id_field || attr_name == db::action_field) {
                                       return false;
                                   }
                                   return true;
                               })),
      relations(std::move(relations)) {
}

std::string db::entity::sql_for_create() const {
    auto mapped_attrs = to_vector<std::string>(this->attributes, [](auto const &pair) { return pair.second.sql(); });
    return db::create_table_sql(this->name, mapped_attrs);
}

std::string db::entity::sql_for_update() const {
    auto mapped_fields = to_vector<std::string>(this->attributes, [](auto const &pair) { return pair.first; });
    return db::update_sql(this->name, mapped_fields, db::equal_field_expr(id_field));
}

std::string db::entity::sql_for_insert() const {
    std::vector<std::string> mapped_fields;
    for (auto const &pair : this->attributes) {
        auto const &field_name = pair.first;
        if (field_name != db::id_field) {
            mapped_fields.push_back(field_name);
        }
    }
    return db::insert_sql(this->name, mapped_fields);
}
