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

using namespace yas;

namespace yas {
namespace db {
    static std::string const version_key = "version";
    static std::string const entities_key = "entities";
    static std::string const attributes_key = "attributes";
    static std::string const relations_key = "relations";
}
}

struct db::model::impl : public base::impl {
    yas::version version;
    entity_map entities;

    impl(CFDictionaryRef const &cf_dict) {
        if (!cf_dict) {
            return;
        }

        auto version_str = get<std::string>(cf_dict, version_key);
        if (version_str.size() > 0) {
            version = yas::version{version_str};
        } else {
            throw "version not found.";
            return;
        }

        CFDictionaryRef cf_entities_dict = get<CFDictionaryRef>(cf_dict, entities_key);
        if (!cf_entities_dict) {
            throw "entities not found";
            return;
        }

        for (auto &cf_entities_pair : each_dictionary{cf_entities_dict}) {
            auto entity_name = to_string((CFStringRef)cf_entities_pair.first);
            if (entity_name.size() == 0) {
                throw "invalid entity name";
                return;
            }

            CFDictionaryRef cf_entity_dict = get<CFDictionaryRef>(cf_entities_dict, entity_name);
            if (!cf_entity_dict) {
                throw "invalid entity dictionary";
                return;
            }

            attribute_map attributes;

            auto const &id_attr = attribute::id_attribute();
            attributes.emplace(std::make_pair(id_attr.name, id_attr));

            auto const &obj_id_attr = attribute::object_id_attribute();
            attributes.emplace(std::make_pair(obj_id_attr.name, obj_id_attr));

            auto const &save_id_attr = attribute::save_id_attribute();
            attributes.emplace(std::make_pair(save_id_attr.name, save_id_attr));

            auto const &action_attr = attribute::action_attribute();
            attributes.emplace(std::make_pair(action_attr.name, action_attr));

            CFDictionaryRef cf_attributes = get<CFDictionaryRef>(cf_entity_dict, attributes_key);
            if (cf_attributes) {
                for (auto &cf_attribute_pair : each_dictionary{cf_attributes}) {
                    std::string attr_name = to_string((CFStringRef)cf_attribute_pair.first);
                    if (attr_name.size() > 0) {
                        CFDictionaryRef cf_attr_dict = get<CFDictionaryRef>(cf_attributes, attr_name);
                        attributes.emplace(std::make_pair(attr_name, db::attribute{attr_name, cf_attr_dict}));
                    }
                }
            }

            relation_map relations;

            CFDictionaryRef cf_relations = get<CFDictionaryRef>(cf_entity_dict, relations_key);
            if (cf_relations) {
                for (auto &cf_relation_pair : each_dictionary{cf_relations}) {
                    std::string relation_name = to_string((CFStringRef)cf_relation_pair.first);
                    CFDictionaryRef cf_relation_dict = get<CFDictionaryRef>(cf_relations, relation_name);
                    if (cf_relation_dict) {
                        db::relation relation{entity_name, std::move(relation_name), cf_relation_dict};
                        relations.emplace(std::make_pair(std::move(relation_name), std::move(relation)));
                    }
                }
            }

            db::entity entity{entity_name, std::move(attributes), std::move(relations)};
            entities.emplace(std::make_pair(entity_name, std::move(entity)));
        }
    }
};

db::model::model(CFDictionaryRef const &cf_dict) : super_class(std::make_unique<impl>(cf_dict)) {
}

yas::version const &db::model::version() const {
    return impl_ptr<impl>()->version;
}

db::model::entity_map const &db::model::entities() const {
    return impl_ptr<impl>()->entities;
}

db::attribute_map const &db::model::attributes(std::string const &entity_name) const {
    return entities().at(entity_name).attributes;
}

db::relation_map const &db::model::relations(std::string const &entity_name) const {
    return entities().at(entity_name).relations;
}

db::attribute const &db::model::attribute(std::string const &entity_name, std::string const &attr_name) const {
    return entities().at(entity_name).attributes.at(attr_name);
}

db::relation const &db::model::relation(std::string const &entity_name, std::string const &rel_name) const {
    return entities().at(entity_name).relations.at(rel_name);
}

bool db::model::entity_exists(std::string const &entity_name) const {
    if (entities().count(entity_name) > 0) {
        return true;
    }
    return false;
}

bool db::model::attribute_exists(std::string const &entity_name, std::string const &attr_name) const {
    if (entity_exists(entity_name)) {
        if (entities().at(entity_name).attributes.count(attr_name) > 0) {
            return true;
        }
    }
    return false;
}

bool db::model::relation_exists(std::string const &entity_name, std::string const &rel_name) const {
    if (entity_exists(entity_name)) {
        if (entities().at(entity_name).relations.count(rel_name) > 0) {
            return true;
        }
    }
    return false;
}

std::string const &db::model::target_entity_name(std::string const &entity_name, std::string const &rel_name) const {
    return entities().at(entity_name).relations.at(rel_name).target_entity_name;
}
