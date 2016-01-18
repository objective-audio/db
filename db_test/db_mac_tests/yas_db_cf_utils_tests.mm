//
//  yas_db_cf_utils_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_cf_utils_tests : XCTestCase

@end

@implementation yas_db_cf_utils_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_to_value_from_cf_string {
    auto cf_string = CFSTR("abc");
    auto value = yas::to_value(cf_string);

    XCTAssertTrue(value.type() == typeid(db::text));
    XCTAssertEqual(value.get<db::text>(), "abc");
}

- (void)test_to_value_from_cf_mutable_string {
    auto cf_mutable_string = CFStringCreateMutable(nullptr, 0);
    CFStringAppendCString(cf_mutable_string, "def", kCFStringEncodingUTF8);
    auto value = yas::to_value(cf_mutable_string);

    XCTAssertTrue(value.type() == typeid(db::text));
    XCTAssertEqual(value.get<db::text>(), "def");
}

- (void)test_to_value_from_integer {
    UInt8 uint8_value = 1;
    UInt16 uint16_value = 2;
    UInt32 uint32_value = 3;
    UInt64 uint64_value = 4;
    SInt8 sint8_value = -1;
    SInt16 sint16_value = -2;
    SInt32 sint32_value = -3;
    SInt64 sint64_value = -4;

    auto const uint8_number = CFNumberCreate(nullptr, kCFNumberSInt8Type, &uint8_value);
    auto const uint16_number = CFNumberCreate(nullptr, kCFNumberSInt16Type, &uint16_value);
    auto const uint32_number = CFNumberCreate(nullptr, kCFNumberSInt32Type, &uint32_value);
    auto const uint64_number = CFNumberCreate(nullptr, kCFNumberSInt64Type, &uint64_value);
    auto const sint8_number = CFNumberCreate(nullptr, kCFNumberSInt8Type, &sint8_value);
    auto const sint16_number = CFNumberCreate(nullptr, kCFNumberSInt16Type, &sint16_value);
    auto const sint32_number = CFNumberCreate(nullptr, kCFNumberSInt32Type, &sint32_value);
    auto const sint64_number = CFNumberCreate(nullptr, kCFNumberSInt64Type, &sint64_value);

    XCTAssertTrue(yas::to_value(uint8_number).type() == typeid(db::integer));
    XCTAssertTrue(yas::to_value(uint16_number).type() == typeid(db::integer));
    XCTAssertTrue(yas::to_value(uint32_number).type() == typeid(db::integer));
    XCTAssertTrue(yas::to_value(uint64_number).type() == typeid(db::integer));
    XCTAssertTrue(yas::to_value(sint8_number).type() == typeid(db::integer));
    XCTAssertTrue(yas::to_value(sint16_number).type() == typeid(db::integer));
    XCTAssertTrue(yas::to_value(sint32_number).type() == typeid(db::integer));
    XCTAssertTrue(yas::to_value(sint64_number).type() == typeid(db::integer));

    XCTAssertEqual(yas::to_value(uint8_number).get<db::integer>(), 1);
    XCTAssertEqual(yas::to_value(uint16_number).get<db::integer>(), 2);
    XCTAssertEqual(yas::to_value(uint32_number).get<db::integer>(), 3);
    XCTAssertEqual(yas::to_value(uint64_number).get<db::integer>(), 4);
    XCTAssertEqual(yas::to_value(sint8_number).get<db::integer>(), -1);
    XCTAssertEqual(yas::to_value(sint16_number).get<db::integer>(), -2);
    XCTAssertEqual(yas::to_value(sint32_number).get<db::integer>(), -3);
    XCTAssertEqual(yas::to_value(sint64_number).get<db::integer>(), -4);
}

- (void)test_to_value_from_float {
    Float32 f32_value = 3.2f;
    Float64 f64_value = 6.4;

    auto const f32_number = CFNumberCreate(nullptr, kCFNumberFloat32Type, &f32_value);
    auto const f64_number = CFNumberCreate(nullptr, kCFNumberFloat64Type, &f64_value);

    XCTAssertTrue(yas::to_value(f32_number).type() == typeid(db::real));
    XCTAssertTrue(yas::to_value(f64_number).type() == typeid(db::real));

    XCTAssertEqual(yas::to_value(f32_number).get<db::real>(), 3.2f);
    XCTAssertEqual(yas::to_value(f64_number).get<db::real>(), 6.4);
}

- (void)test_to_value_from_cf_data {
    std::vector<UInt8> vec{0, 1, 2, 3};
    auto cf_data = CFDataCreate(nullptr, vec.data(), vec.size());

    auto data_value = yas::to_value(cf_data);

    XCTAssertTrue(data_value.type() == typeid(db::blob));
    XCTAssertEqual(data_value.get<db::blob>().size(), 4);

    UInt8 const *ptr = (UInt8 const *)data_value.get<db::blob>().data();
    XCTAssertEqual(ptr[0], 0);
    XCTAssertEqual(ptr[1], 1);
    XCTAssertEqual(ptr[2], 2);
    XCTAssertEqual(ptr[3], 3);
}

- (void)test_to_value_from_cf_mutable_data {
    std::vector<UInt8> vec{4, 5, 6};
    auto cf_mutable_data = CFDataCreateMutable(nullptr, vec.size());
    CFDataAppendBytes(cf_mutable_data, vec.data(), vec.size());

    auto data_value = yas::to_value(cf_mutable_data);

    XCTAssertTrue(data_value.type() == typeid(db::blob));
    XCTAssertEqual(data_value.get<db::blob>().size(), 3);

    UInt8 const *ptr = (UInt8 const *)data_value.get<db::blob>().data();
    XCTAssertEqual(ptr[0], 4);
    XCTAssertEqual(ptr[1], 5);
    XCTAssertEqual(ptr[2], 6);
}

- (void)test_to_value_from_nullptr {
    auto null_value = yas::to_value(nullptr);
    XCTAssertTrue(null_value.type() == typeid(db::null));
}

- (void)test_get_string_from_dictionary {
    NSDictionary *dict = @{ @"a": @"b" };
    auto string_a = yas::get<std::string>((__bridge CFDictionaryRef)dict, "a");

    XCTAssertEqual(string_a, "b");

    auto string_x = yas::get<std::string>((__bridge CFDictionaryRef)dict, "x");

    XCTAssertEqual(string_x.size(), 0);
}

- (void)test_get_value_from_dictionary {
    NSDictionary *dict = @{ @"a": @5 };
    auto value_a = yas::get<db::value>((__bridge CFDictionaryRef)dict, "a");

    XCTAssertTrue(value_a.type() == typeid(db::integer));
    XCTAssertEqual(value_a.get<db::integer>(), 5);

    auto value_x = yas::get<db::value>((__bridge CFDictionaryRef)dict, "x");

    XCTAssertTrue(value_x.type() == typeid(db::null));
}

- (void)test_get_bool_from_dictionary {
    NSDictionary *dict = @{ @"a": @YES };
    auto bool_a = yas::get<bool>((__bridge CFDictionaryRef)dict, "a");

    XCTAssertEqual(bool_a, true);

    auto bool_x = yas::get<bool>((__bridge CFDictionaryRef)dict, "x");

    XCTAssertEqual(bool_x, false);
}

- (void)test_get_dictionary_from_dictionary {
    NSDictionary *dict = @{ @"a": @{@"b": @"c"} };
    auto cf_dict_a = yas::get<CFDictionaryRef>((__bridge CFDictionaryRef)dict, "a");

    XCTAssertTrue(cf_dict_a);
    XCTAssertEqual(CFDictionaryGetCount(cf_dict_a), 1);
    XCTAssertTrue(CFDictionaryContainsKey(cf_dict_a, CFSTR("b")));
    XCTAssertTrue(CFEqual(CFDictionaryGetValue(cf_dict_a, CFSTR("b")), CFSTR("c")));

    auto cf_dict_x = yas::get<CFDictionaryRef>((__bridge CFDictionaryRef)dict, "x");

    XCTAssertFalse(cf_dict_x);
}

- (void)test_get_array_from_dictionary {
    NSDictionary *dict = @{ @"d": @[@"e", @"f"] };
    auto cf_array_d = yas::get<CFArrayRef>((__bridge CFDictionaryRef)dict, "d");

    XCTAssertTrue(cf_array_d);
    XCTAssertEqual(CFArrayGetCount(cf_array_d), 2);
    XCTAssertTrue(CFEqual(CFArrayGetValueAtIndex(cf_array_d, 0), CFSTR("e")));
    XCTAssertTrue(CFEqual(CFArrayGetValueAtIndex(cf_array_d, 1), CFSTR("f")));

    auto cf_array_x = yas::get<CFArrayRef>((__bridge CFDictionaryRef)dict, "x");

    XCTAssertFalse(cf_array_x);
}

@end
