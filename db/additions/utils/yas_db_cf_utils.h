//
//  yas_db_cf_utils.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>

#include <string>

namespace yas::db {
class value;
}

namespace yas {
[[nodiscard]] db::value to_value(CFTypeRef const &cf_obj);

template <typename T>
[[nodiscard]] T get(CFDictionaryRef const dict, std::string const &key);
}  // namespace yas
