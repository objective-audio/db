//
//  yas_db_order.h
//

#pragma once

#include <string>

namespace yas {
namespace db {
    enum class order {
        ascending,
        descending,
    };

    struct field_order {
        std::string const field;
        db::order const order;

        field_order(std::string const &field, db::order const order);

        std::string sql() const;
    };
}
}
