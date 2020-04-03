//
//  yas_db_select_option.h
//

#pragma once

#include <string>

#include "yas_db_value.h"

namespace yas::db {
enum class order {
    ascending,
    descending,
};

struct field_order final {
    std::string field = "";
    db::order order = db::order::ascending;

    std::string sql() const;
};

struct range final {
    uint64_t location = 0;
    uint64_t length = 0;

    bool is_empty() const;

    std::string sql() const;
};

db::range const &empty_range();

struct select_option final {
    std::string table = "";
    std::vector<std::string> fields = {"*"};
    std::string where_exprs = "";
    db::value_map_t arguments = {};
    std::vector<db::field_order> field_orders = {};
    db::range limit_range = db::empty_range();
    std::string group_by = "";
    bool distinct = false;
};
}  // namespace yas::db
