//
//  yas_db_range.cpp
//

#include "yas_db_range.h"

using namespace yas;

db::range::range(UInt64 const location, UInt64 const length) : location(location), length(length) {
}

std::string db::range::sql() const {
    return std::to_string(location) + ", " + std::to_string(length);
}