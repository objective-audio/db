//
//  yas_db_order.cpp
//

#include "yas_db_order.h"

using namespace yas;

db::field_order::field_order(std::string const &field, db::order const order) : field(field), order(order) {
}

std::string db::field_order::sql() const {
    return field + (order == db::order::ascending ? " asc" : " desc");
}