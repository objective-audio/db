//
//  yas_db_select_option.cpp
//

#include "yas_db_select_option.h"

using namespace yas;

#pragma mark - db::field_order

std::string db::field_order::sql() const {
    return field + (order == db::order::ascending ? " asc" : " desc");
}

#pragma mark - db::range

bool db::range::is_empty() const {
    return length == 0;
}

std::string db::range::sql() const {
    return std::to_string(location) + ", " + std::to_string(length);
}

const db::range &db::range::empty() {
    static range const _empty_range = db::range{0, 0};
    return _empty_range;
}