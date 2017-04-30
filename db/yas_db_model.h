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

    using entity_map_t = std::unordered_map<std::string, db::entity>;
    using index_map_t = std::unordered_map<std::string, db::index>;

    class model : public base {
        class impl;

       public:
        model(CFDictionaryRef const &dict);

        yas::version const &version() const;
        db::entity_map_t const &entities() const;
        db::index_map_t const &indices() const;

        db::entity const &entity(std::string const &entity_name) const;
        db::attribute_map_t const &attributes(std::string const &entity_name) const;
        db::relation_map_t const &relations(std::string const &entity_name) const;
        db::attribute const &attribute(std::string const &entity_name, std::string const &attr_name) const;
        db::relation const &relation(std::string const &entity_name, std::string const &rel_name) const;
        db::index const &index(std::string const &index_name) const;

        bool entity_exists(std::string const &entity_name) const;
        bool attribute_exists(std::string const &entity_name, std::string const &attr_name) const;
        bool relation_exists(std::string const &entity_name, std::string const &rel_name) const;
        bool index_exists(std::string const &index_name) const;
    };
}
}
