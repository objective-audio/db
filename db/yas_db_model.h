//
//  yas_db_model.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <memory>
#include <string>
#include "yas_db_additional_protocol.h"
#include "yas_base.h"

namespace yas {
class version;
}

namespace yas::db {
class model : public base {
    class impl;

   public:
    struct args {
        yas::version const version;
        db::entity_map_t const entities;
        db::index_map_t const indices;
    };

    explicit model(model_args);
    explicit model(args);
    explicit model(CFDictionaryRef const &dict);
    model(std::nullptr_t);

    yas::version const &version() const;
    db::entity_map_t const &entities() const;
    db::index_map_t const &indices() const;

    db::entity const &entity(std::string const &entity_name) const;
    db::attribute_map_t const &attributes(std::string const &entity_name) const;
    db::attribute_map_t const &custom_attributes(std::string const &entity_name) const;
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
