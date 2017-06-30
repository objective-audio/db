//
//  yas_db_model.cpp
//

#include <unordered_map>
#include <vector>
#include "yas_cf_utils.h"
#include "yas_db_cf_utils.h"
#include "yas_db_model.h"
#include "yas_each_dictionary.h"
#include "yas_version.h"
#include "yas_db_entity.h"
#include "yas_db_index.h"
#include "yas_db_attribute.h"
#include "yas_db_relation.h"

using namespace yas;

namespace yas {
namespace db {
    static std::string const version_key = "version";
    static std::string const entities_key = "entities";
    static std::string const indices_key = "indices";
    static std::string const attributes_key = "attributes";
    static std::string const relations_key = "relations";
}
}

struct db::model::impl : public base::impl {
    yas::version _version;
    db::entity_map_t _entities;
    db::index_map_t _indices;

    impl(CFDictionaryRef const &cf_dict) {
        if (!cf_dict) {
            return;
        }

        std::string version_str = get<std::string>(cf_dict, db::version_key);
        if (version_str.size() > 0) {
            this->_version = yas::version{version_str};
        } else {
            throw "version not found.";
            return;
        }

        CFDictionaryRef cf_entities_dict = get<CFDictionaryRef>(cf_dict, db::entities_key);
        if (!cf_entities_dict) {
            throw "entities not found";
            return;
        }

        std::unordered_map<std::string, std::pair<db::attribute_map_t, db::relation_map_t>> entity_params;
        std::unordered_map<std::string, db::string_set_map_t> entity_inv_rel_names;

        for (auto &cf_entities_pair : each_dictionary(cf_entities_dict)) {
            std::string entity_name = to_string((CFStringRef)cf_entities_pair.first);
            if (entity_name.size() == 0) {
                throw "invalid entity name";
                return;
            }

            CFDictionaryRef cf_entity_dict = get<CFDictionaryRef>(cf_entities_dict, entity_name);
            if (!cf_entity_dict) {
                throw "invalid entity dictionary";
                return;
            }

            db::attribute_map_t attributes;

            db::attribute const &id_attr = db::attribute::id_attribute();
            attributes.emplace(id_attr.name, id_attr);

            db::attribute const &obj_id_attr = db::attribute::object_id_attribute();
            attributes.emplace(obj_id_attr.name, obj_id_attr);

            db::attribute const &save_id_attr = db::attribute::save_id_attribute();
            attributes.emplace(save_id_attr.name, save_id_attr);

            db::attribute const &action_attr = db::attribute::action_attribute();
            attributes.emplace(action_attr.name, action_attr);

            CFDictionaryRef cf_attributes = get<CFDictionaryRef>(cf_entity_dict, db::attributes_key);
            if (cf_attributes) {
                for (auto &cf_attribute_pair : each_dictionary(cf_attributes)) {
                    std::string attr_name = to_string((CFStringRef)cf_attribute_pair.first);
                    if (attr_name.size() > 0) {
                        CFDictionaryRef cf_attr_dict = get<CFDictionaryRef>(cf_attributes, attr_name);
                        attributes.emplace(attr_name, db::attribute{attr_name, cf_attr_dict});
                    }
                }
            }

            db::relation_map_t relations;

            CFDictionaryRef cf_relations = get<CFDictionaryRef>(cf_entity_dict, db::relations_key);
            if (cf_relations) {
                for (auto &cf_relation_pair : each_dictionary(cf_relations)) {
                    std::string relation_name = to_string((CFStringRef)cf_relation_pair.first);
                    CFDictionaryRef cf_relation_dict = get<CFDictionaryRef>(cf_relations, relation_name);
                    if (cf_relation_dict) {
                        db::relation relation{entity_name, relation_name, cf_relation_dict};

                        std::string const &tgt_entity_name = relation.target_entity_name;
                        if (entity_inv_rel_names.count(tgt_entity_name) == 0) {
                            entity_inv_rel_names.insert(std::make_pair(tgt_entity_name, db::string_set_map_t{}));
                        }
                        auto &inv_rel_names = entity_inv_rel_names.at(tgt_entity_name);
                        if (inv_rel_names.count(entity_name) == 0) {
                            inv_rel_names.insert(std::make_pair(entity_name, db::string_set_t{}));
                        }
                        inv_rel_names.at(entity_name).insert(relation_name);

                        relations.emplace(std::move(relation_name), std::move(relation));
                    }
                }
            }

            entity_params.emplace(entity_name, std::make_pair(std::move(attributes), std::move(relations)));
        }

        for (auto &entity_pair : entity_params) {
            std::string const &entity_name = entity_pair.first;
            db::string_set_map_t inv_rel_names;
            if (entity_inv_rel_names.count(entity_name)) {
                inv_rel_names = std::move(entity_inv_rel_names.at(entity_name));
            }
            db::entity entity{entity_name, std::move(entity_pair.second.first), std::move(entity_pair.second.second),
                              std::move(inv_rel_names)};
            this->_entities.emplace(entity_name, std::move(entity));
        }

        CFDictionaryRef cf_indices_dict = get<CFDictionaryRef>(cf_dict, db::indices_key);
        if (cf_indices_dict) {
            for (auto &cf_index_pair : each_dictionary(cf_indices_dict)) {
                std::string index_name = to_string((CFStringRef)cf_index_pair.first);
                if (index_name.size() == 0) {
                    throw "invalid index name";
                    return;
                }

                CFDictionaryRef cf_index_dict = get<CFDictionaryRef>(cf_indices_dict, index_name);
                if (!cf_index_dict) {
                    throw "invalid index dictionary";
                    return;
                }

                this->_indices.emplace(index_name, db::index{index_name, cf_index_dict});
            }
        }
    }
};

db::model::model(CFDictionaryRef const &cf_dict) : base(std::make_unique<impl>(cf_dict)) {
}

yas::version const &db::model::version() const {
    return impl_ptr<impl>()->_version;
}

db::entity_map_t const &db::model::entities() const {
    return impl_ptr<impl>()->_entities;
}

db::index_map_t const &db::model::indices() const {
    return impl_ptr<impl>()->_indices;
}

db::entity const &db::model::entity(std::string const &entity_name) const {
    return this->entities().at(entity_name);
}

db::attribute_map_t const &db::model::attributes(std::string const &entity_name) const {
    return this->entities().at(entity_name).all_attributes;
}

db::attribute_map_t const &db::model::custom_attributes(std::string const &entity_name) const {
    return this->entities().at(entity_name).custom_attributes;
}

db::relation_map_t const &db::model::relations(std::string const &entity_name) const {
    return this->entities().at(entity_name).relations;
}

db::attribute const &db::model::attribute(std::string const &entity_name, std::string const &attr_name) const {
    return this->entities().at(entity_name).all_attributes.at(attr_name);
}

db::relation const &db::model::relation(std::string const &entity_name, std::string const &rel_name) const {
    return this->entities().at(entity_name).relations.at(rel_name);
}

db::index const &db::model::index(std::string const &index_name) const {
    return this->indices().at(index_name);
}

bool db::model::entity_exists(std::string const &entity_name) const {
    return this->entities().count(entity_name) > 0;
}

bool db::model::attribute_exists(std::string const &entity_name, std::string const &attr_name) const {
    if (this->entity_exists(entity_name)) {
        if (this->entities().at(entity_name).all_attributes.count(attr_name) > 0) {
            return true;
        }
    }
    return false;
}

bool db::model::relation_exists(std::string const &entity_name, std::string const &rel_name) const {
    if (this->entity_exists(entity_name)) {
        if (this->entities().at(entity_name).relations.count(rel_name) > 0) {
            return true;
        }
    }
    return false;
}

bool db::model::index_exists(std::string const &index_name) const {
    return this->indices().count(index_name) > 0;
}
