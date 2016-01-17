//
//  yas_db_select_option.h
//

#pragma once

#include <MacTypes.h>
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
        UInt64 location = 0;
        UInt64 length = 0;

        bool is_empty() const;

        std::string sql() const;

        static const range &empty();
    };

    struct select_option {
        std::vector<std::string> fields = {"*"};
        std::string where_exprs = "";
        db::value_map arguments = {};
        std::vector<db::field_order> field_orders = {};
        db::range limit_range = db::range::empty();
    };
}
}
