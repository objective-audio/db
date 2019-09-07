//
//  yas_db_model.h
//

#pragma once

#include <memory>
#include <string>
#include "yas_db_additional_protocol.h"

namespace yas {
class version;
}

namespace yas::db {
struct model {
    explicit model(model_args);

    yas::version const &version() const;
    db::entity_map_t const &entities() const;
    db::index_map_t const &indices() const;

    db::entity const &entity(std::string const &entity) const;
    db::attribute_map_t const &attributes(std::string const &entity) const;
    db::attribute_map_t const &custom_attributes(std::string const &entity) const;
    db::relation_map_t const &relations(std::string const &entity) const;
    db::attribute const &attribute(std::string const &entity, std::string const &attribute) const;
    db::relation const &relation(std::string const &entity, std::string const &relation) const;
    db::index const &index(std::string const &index_name) const;

    bool entity_exists(std::string const &entity) const;
    bool attribute_exists(std::string const &entity, std::string const &attribute) const;
    bool relation_exists(std::string const &entity, std::string const &relation) const;
    bool index_exists(std::string const &index_name) const;

   private:
    class impl;

    std::shared_ptr<impl> _impl;
};
}  // namespace yas::db
