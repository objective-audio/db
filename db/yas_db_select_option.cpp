//
//  yas_db_select_option.cpp
//

#include "yas_db_select_option.h"

using namespace yas;

#pragma mark - db::field_order

std::string db::field_order::sql() const {
    return this->field + (this->order == db::order::ascending ? " ASC" : " DESC");
}

#pragma mark - db::range

bool db::range::is_empty() const {
    return this->length == 0;
}

std::string db::range::sql() const {
    return std::to_string(this->location) + ", " + std::to_string(this->length);
}

const db::range &db::range::empty() {
    static db::range const _empty_range = db::range{0, 0};
    return _empty_range;
}
