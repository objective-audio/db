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
#include "yas_db_index.h"
#include "yas_db_relation.h"

namespace yas {
class version;

namespace db {
    class entity;

    class model : public base {
        class impl;

       public:
        using entity_map = std::unordered_map<std::string, entity>;
        using index_map = std::unordered_map<std::string, index>;

        model(CFDictionaryRef const &dict);

        yas::version const &version() const;
        entity_map const &entities() const;
        index_map const &indices() const;

        entity const &entity(std::string const &entity_name) const;
        attribute_map const &attributes(std::string const &entity_name) const;
        relation_map const &relations(std::string const &entity_name) const;
        attribute const &attribute(std::string const &entity_name, std::string const &attr_name) const;
        relation const &relation(std::string const &entity_name, std::string const &rel_name) const;
        index const &index(std::string const &index_name) const;

        bool entity_exists(std::string const &entity_name) const;
        bool attribute_exists(std::string const &entity_name, std::string const &attr_name) const;
        bool relation_exists(std::string const &entity_name, std::string const &rel_name) const;
        bool index_exists(std::string const &index_name) const;
    };
}
}
