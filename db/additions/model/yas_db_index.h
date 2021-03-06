//
//  yas_db_index.h
//

#pragma once

#include <string>
#include <vector>

namespace yas::db {
class index_args;

class index final {
   public:
    std::string const name;
    std::string const entity;
    std::vector<std::string> const attributes;

    explicit index(index_args);

    [[nodiscard]] std::string sql_for_create() const;
};
}  // namespace yas::db
