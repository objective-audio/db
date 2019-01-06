//
//  yas_db_entity.cpp
//

#include "yas_db_entity.h"
#include <cpp_utils/yas_stl_utils.h>
#include "yas_db_additional_protocol.h"
#include "yas_db_attribute.h"
#include "yas_db_relation.h"
#include "yas_db_sql_utils.h"

using namespace yas;

namespace yas {
static db::attribute_map_t make_attributes(std::vector<db::attribute_args> const &args_vec) {
    db::attribute_map_t attributes;

    for (db::attribute_args const &args : args_vec) {
        attributes.emplace(args.name, db::attribute{args});
    }

    return attributes;
}

static db::attribute_map_t make_all_attributes(std::vector<db::attribute_args> const &args_vec) {
    db::attribute_map_t attributes = make_attributes(args_vec);

    attributes.reserve(args_vec.size() + 4);

    db::attribute const &id_attr = db::attribute::id_attribute();
    attributes.emplace(id_attr.name, id_attr);

    db::attribute const &obj_id_attr = db::attribute::object_id_attribute();
    attributes.emplace(obj_id_attr.name, obj_id_attr);

    db::attribute const &save_id_attr = db::attribute::save_id_attribute();
    attributes.emplace(save_id_attr.name, save_id_attr);

    db::attribute const &action_attr = db::attribute::action_attribute();
    attributes.emplace(action_attr.name, action_attr);

    return attributes;
}

static db::relation_map_t make_relations(std::vector<db::relation_args> &&args_vec, std::string const &source) {
    db::relation_map_t relations;
    relations.reserve(args_vec.size());

    for (db::relation_args &args : args_vec) {
        std::string name = args.name;
        relations.emplace(std::move(name), db::relation{std::move(args), source});
    }

    return relations;
}
}  // namespace yas

db::entity::entity(entity_args args, db::string_set_map_t inv_rel_names)
    : name(std::move(args.name)),
      all_attributes(make_all_attributes(args.attributes)),
      custom_attributes(make_attributes(args.attributes)),
      relations(make_relations(std::move(args.relations), this->name)),
      inverse_relation_names(std::move(inv_rel_names)) {
}

std::string db::entity::sql_for_create() const {
    auto mapped_attrs =
        to_vector<std::string>(this->all_attributes, [](auto const &pair) { return pair.second.sql(); });
    return db::create_table_sql(this->name, mapped_attrs);
}

std::string db::entity::sql_for_update() const {
    auto mapped_fields = to_vector<std::string>(this->all_attributes, [](auto const &pair) { return pair.first; });
    return db::update_sql(this->name, mapped_fields, db::equal_field_expr(db::pk_id_field));
}

std::string db::entity::sql_for_insert() const {
    std::vector<std::string> mapped_fields;
    for (auto const &pair : this->all_attributes) {
        std::string const &field_name = pair.first;
        if (field_name != db::pk_id_field) {
            mapped_fields.push_back(field_name);
        }
    }
    return db::insert_sql(this->name, mapped_fields);
}
