//
//  yas_db_cf_utils.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include "yas_db_value.h"

namespace yas {
db::value to_value(CFTypeRef const &cf_obj);

template <typename T>
T get(CFDictionaryRef const dict, std::string const &key);
}
