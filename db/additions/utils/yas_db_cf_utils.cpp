//
//  yas_db_cf_utils.cpp
//

#include "yas_db_cf_utils.h"

#include <cpp_utils/yas_cf_utils.h>

#include "yas_db_value.h"

using namespace yas;

db::value yas::to_value(CFTypeRef const &cf_obj) {
    if (!cf_obj) {
        return nullptr;
    }

    CFTypeID const type_id = CFGetTypeID(cf_obj);

    if (type_id == CFStringGetTypeID()) {
        CFStringRef const cf_string = (CFStringRef)cf_obj;
        return db::value{to_string(cf_string)};
    } else if (type_id == CFNumberGetTypeID()) {
        CFNumberRef const cf_number = (CFNumberRef)cf_obj;
        CFNumberType const number_type = CFNumberGetType(cf_number);

        switch (number_type) {
            case kCFNumberFloat32Type:
            case kCFNumberFloat64Type:
            case kCFNumberFloatType:
            case kCFNumberDoubleType:
            case kCFNumberCGFloatType: {
                double float64_value;
                if (CFNumberGetValue(cf_number, kCFNumberFloat64Type, &float64_value)) {
                    return db::value{float64_value};
                }
            } break;

            default: {
                int64_t int64_value;
                if (CFNumberGetValue(cf_number, kCFNumberSInt64Type, &int64_value)) {
                    return db::value{int64_value};
                }
            } break;
        }
    } else if (type_id == CFBooleanGetTypeID()) {
        CFBooleanRef const cf_boolean = (CFBooleanRef)cf_obj;
        return db::value{CFBooleanGetValue(cf_boolean)};
    } else if (type_id == CFDataGetTypeID()) {
        CFDataRef cf_data = (CFDataRef)cf_obj;
        return db::value{CFDataGetBytePtr(cf_data), static_cast<std::size_t>(CFDataGetLength(cf_data))};
    }

    return nullptr;
}

template <>
std::string yas::get(CFDictionaryRef const dict, std::string const &key) {
    return to_string((CFStringRef)CFDictionaryGetValue(dict, to_cf_object(key)));
}

template <>
db::value yas::get(CFDictionaryRef const dict, std::string const &key) {
    return to_value(CFDictionaryGetValue(dict, to_cf_object(key)));
}

template <>
bool yas::get(CFDictionaryRef const dict, std::string const &key) {
    db::value db_value = get<db::value>(dict, key);
    if (db_value) {
        return db_value.get<db::integer>() != 0;
    }
    return false;
}

template <>
std::vector<std::string> yas::get(CFDictionaryRef const dict, std::string const &key) {
    CFArrayRef array = (CFArrayRef)CFDictionaryGetValue(dict, to_cf_object(key));
    if (CFGetTypeID(array) == CFArrayGetTypeID()) {
        return to_vector<std::string>(array,
                                      [](CFTypeRef const &cf_string) { return to_string((CFStringRef)cf_string); });
    }
    return {};
}

template <>
CFDictionaryRef yas::get(CFDictionaryRef const dict, std::string const &key) {
    CFTypeRef cf_obj = CFDictionaryGetValue(dict, to_cf_object(key));
    if (cf_obj && CFGetTypeID(cf_obj) == CFDictionaryGetTypeID()) {
        return (CFDictionaryRef)cf_obj;
    }
    return nullptr;
}

template <>
CFArrayRef yas::get(CFDictionaryRef const dict, std::string const &key) {
    CFTypeRef cf_obj = CFDictionaryGetValue(dict, to_cf_object(key));
    if (cf_obj && CFGetTypeID(cf_obj) == CFArrayGetTypeID()) {
        return (CFArrayRef)cf_obj;
    }
    return nullptr;
}
