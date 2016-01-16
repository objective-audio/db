//
//  yas_db_model.cpp
//

#include <unordered_map>
#include <vector>
#include "yas_cf_utils.h"
#include "yas_db_cf_utils.h"
#include "yas_db_model.h"
#include "yas_each_dictionary.h"

using namespace yas;

namespace yas {
namespace db {
    static auto constexpr version_key = "version";
    static auto constexpr entities_key = "entities";
    static auto constexpr attributes_key = "attributes";
    static auto constexpr relations_key = "relations";
}
}

struct db::model::impl : public base::impl {
    yas::version version;
    entities_map entities;

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

            auto const &removed_attr = attribute::removed_attribute();
            attributes.emplace(std::make_pair(removed_attr.name, removed_attr));

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

db::model::entities_map const &db::model::entities() const {
    return impl_ptr<impl>()->entities;
}
