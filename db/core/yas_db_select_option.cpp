//
//  yas_db_select_option.cpp
//

#include "yas_db_select_option.h"

using namespace yas;
using namespace yas::db;

#pragma mark - db::field_order

std::string field_order::sql() const {
    return this->field + (this->order == db::order::ascending ? " ASC" : " DESC");
}

#pragma mark - range

bool range::is_empty() const {
    return this->length == 0;
}

std::string range::sql() const {
    return std::to_string(this->location) + ", " + std::to_string(this->length);
}

range const &db::empty_range() {
    static range const _empty_range = range{0, 0};
    return _empty_range;
}
