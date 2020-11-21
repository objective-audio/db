//
//  yas_db_model.h
//

#pragma once

#include <db/yas_db_additional_protocol.h>

#include <memory>
#include <string>

namespace yas {
class version;
}

namespace yas::db {
struct model final {
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
    struct args {
        yas::version const version;
        db::entity_map_t const entities;
        db::index_map_t const indices;
    };

    args _args;

    static args to_args(model_args &&args);
};
}  // namespace yas::db
