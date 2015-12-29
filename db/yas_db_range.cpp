//
//  yas_db_range.cpp
//

#include "yas_db_range.h"

using namespace yas;

db::range::range(UInt64 const location, UInt64 const length) : location(location), length(length) {
}

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