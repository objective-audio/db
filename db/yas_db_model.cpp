//
//  yas_db_model.cpp
//

#include "yas_db_model.h"

#include <unordered_map>
#include <vector>

#include "yas_db_attribute.h"
#include "yas_db_entity.h"
#include "yas_db_index.h"
#include "yas_db_relation.h"

using namespace yas;

namespace yas::db {
static std::unordered_map<std::string, db::string_set_map_t> make_inverse_relation_names(
    std::vector<db::entity_args> const &enitity_args_vec) {
    std::unordered_map<std::string, db::string_set_map_t> entity_inv_rel_names;

    for (db::entity_args const &entity : enitity_args_vec) {
        std::string const &entity_name = entity.name;
        for (db::relation_args const &relation : entity.relations) {
            std::string const &tgt_entity_name = relation.target;

            if (entity_inv_rel_names.count(tgt_entity_name) == 0) {
                entity_inv_rel_names.insert(std::make_pair(tgt_entity_name, db::string_set_map_t{}));
            }

            auto &inv_rel_names = entity_inv_rel_names.at(tgt_entity_name);
            if (inv_rel_names.count(entity_name) == 0) {
                inv_rel_names.insert(std::make_pair(entity_name, db::string_set_t{}));
            }

            inv_rel_names.at(entity_name).insert(relation.name);
        }
    }

    return entity_inv_rel_names;
}
}  // namespace yas::db

db::model::model(model_args args) : _args(to_args(std::move(args))) {
}

yas::version const &db::model::version() const {
    return this->_args.version;
}

db::entity_map_t const &db::model::entities() const {
    return this->_args.entities;
}

db::index_map_t const &db::model::indices() const {
    return this->_args.indices;
}

db::entity const &db::model::entity(std::string const &entity) const {
    return this->entities().at(entity);
}

db::attribute_map_t const &db::model::attributes(std::string const &entity) const {
    return this->entities().at(entity).all_attributes;
}

db::attribute_map_t const &db::model::custom_attributes(std::string const &entity) const {
    return this->entities().at(entity).custom_attributes;
}

db::relation_map_t const &db::model::relations(std::string const &entity) const {
    return this->entities().at(entity).relations;
}

db::attribute const &db::model::attribute(std::string const &entity, std::string const &attr_name) const {
    return this->entities().at(entity).all_attributes.at(attr_name);
}

db::relation const &db::model::relation(std::string const &entity, std::string const &rel_name) const {
    return this->entities().at(entity).relations.at(rel_name);
}

db::index const &db::model::index(std::string const &index_name) const {
    return this->indices().at(index_name);
}

bool db::model::entity_exists(std::string const &entity) const {
    return this->entities().count(entity) > 0;
}

bool db::model::attribute_exists(std::string const &entity, std::string const &attr_name) const {
    if (this->entity_exists(entity)) {
        if (this->entities().at(entity).all_attributes.count(attr_name) > 0) {
            return true;
        }
    }
    return false;
}

bool db::model::relation_exists(std::string const &entity, std::string const &rel_name) const {
    if (this->entity_exists(entity)) {
        if (this->entities().at(entity).relations.count(rel_name) > 0) {
            return true;
        }
    }
    return false;
}

bool db::model::index_exists(std::string const &index_name) const {
    return this->indices().count(index_name) > 0;
}

db::model::args db::model::to_args(model_args &&args) {
    auto entity_inv_rel_names = make_inverse_relation_names(args.entities);

    db::entity_map_t entities;
    entities.reserve(args.entities.size());

    for (db::entity_args &entity_args : args.entities) {
        db::string_set_map_t inv_rel_names;
        if (entity_inv_rel_names.count(entity_args.name)) {
            inv_rel_names = std::move(entity_inv_rel_names.at(entity_args.name));
        }

        std::string name = entity_args.name;
        entities.emplace(std::move(name), db::entity{{.name = std::move(entity_args.name),
                                                      .attributes = std::move(entity_args.attributes),
                                                      .relations = std::move(entity_args.relations)},
                                                     std::move(inv_rel_names)});
    }

    db::index_map_t indices;
    indices.reserve(args.indices.size());

    for (db::index_args &index_args : args.indices) {
        std::string name = index_args.name;
        indices.emplace(std::move(name), db::index{std::move(index_args)});
    }

    return {.version = std::move(args.version), .entities = std::move(entities), .indices = std::move(indices)};
}
