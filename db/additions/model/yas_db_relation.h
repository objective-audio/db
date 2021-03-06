//
//  yas_db_relation.h
//

#pragma once

#include <string>

namespace yas::db {
class relation_args;

struct relation final {
    std::string const name;
    std::string const source;
    std::string const target;
    bool const many;

    std::string const table;

    explicit relation(relation_args, std::string source);

    [[nodiscard]] std::string sql_for_create() const;
    [[nodiscard]] std::string sql_for_insert() const;
};
}  // namespace yas::db
