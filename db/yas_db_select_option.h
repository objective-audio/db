//
//  yas_db_select_option.h
//

#pragma once

#include <string>
#include "yas_db_value.h"

namespace yas {
namespace db {
    enum class order {
        ascending,
        descending,
    };

    struct field_order {
        std::string field = "";
        db::order order = db::order::ascending;

        std::string sql() const;
    };

    struct range {
        uint64_t location = 0;
        uint64_t length = 0;

        bool is_empty() const;

        std::string sql() const;

        static const db::range &empty();
    };

    struct select_option {
        std::string table = "";
        std::vector<std::string> fields = {"*"};
        std::string where_exprs = "";
        db::value_map_t arguments = {};
        std::vector<db::field_order> field_orders = {};
        db::range limit_range = db::range::empty();
    };
}
}
