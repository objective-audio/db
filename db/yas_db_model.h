//
//  yas_db_model.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <memory>
#include <string>
#include "yas_base.h"
#include "yas_db_attribute.h"
#include "yas_db_entity.h"
#include "yas_db_relation.h"

namespace yas {
class version;

namespace db {
    class entity;

    class model : public base {
        using super_class = base;

       public:
        using entity_map = std::unordered_map<std::string, entity>;

        model(CFDictionaryRef const &dict);

        yas::version const &version() const;
        entity_map const &entities() const;

        attribute_map attributes(std::string const &entity_name);
        relation_map relations(std::string const &entity_name);

        bool entity_exists(std::string const &entity_name) const;
        bool attribute_exists(std::string const &entity_name, std::string const &attr_name) const;
        bool relation_exists(std::string const &entity_name, std::string const &rel_name) const;

        std::string const &target_entity_name(std::string const &entity_name, std::string const &rel_name) const;

       private:
        class impl;
    };
}
}
