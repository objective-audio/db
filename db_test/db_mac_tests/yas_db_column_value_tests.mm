//
//  yas_db_value_tests.mm
//

#import "yas_db_test_utils.h"

@interface yas_db_value_tests : XCTestCase

@end

@implementation yas_db_value_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create_integer_value {
    yas::db::value value{yas::db::integer::type(1)};
    XCTAssertTrue(value.type() == typeid(yas::db::integer));
    XCTAssertEqual(value.get<yas::db::integer>(), 1);

    XCTAssertEqual(value.get<yas::db::real>(), 0.0);
    XCTAssertEqual(value.get<yas::db::text>(), std::string{});
}

- (void)test_create_every_integer_value {
    yas::db::value uint8_value{UInt8{UINT8_MAX}};
    yas::db::value sint8_value{SInt8{INT8_MAX}};
    yas::db::value uint16_value{UInt16{UINT16_MAX}};
    yas::db::value sint16_value{SInt16{INT16_MAX}};
    yas::db::value uint32_value{UInt32{UINT32_MAX}};
    yas::db::value sint32_value{SInt32{INT32_MAX}};
    yas::db::value uint64_value{UInt64{UINT64_MAX}};
    yas::db::value sint64_value{SInt64{INT64_MAX}};

    XCTAssertTrue(uint8_value.type() == typeid(yas::db::integer));
    XCTAssertTrue(sint8_value.type() == typeid(yas::db::integer));
    XCTAssertTrue(uint16_value.type() == typeid(yas::db::integer));
    XCTAssertTrue(sint16_value.type() == typeid(yas::db::integer));
    XCTAssertTrue(uint32_value.type() == typeid(yas::db::integer));
    XCTAssertTrue(sint32_value.type() == typeid(yas::db::integer));
    XCTAssertTrue(uint64_value.type() == typeid(yas::db::integer));
    XCTAssertTrue(sint64_value.type() == typeid(yas::db::integer));

    XCTAssertEqual(uint8_value.get<yas::db::integer>(), UINT8_MAX);
    XCTAssertEqual(sint8_value.get<yas::db::integer>(), INT8_MAX);
    XCTAssertEqual(uint16_value.get<yas::db::integer>(), UINT16_MAX);
    XCTAssertEqual(sint16_value.get<yas::db::integer>(), INT16_MAX);
    XCTAssertEqual(uint32_value.get<yas::db::integer>(), UINT32_MAX);
    XCTAssertEqual(sint32_value.get<yas::db::integer>(), INT32_MAX);
    XCTAssertEqual(uint64_value.get<yas::db::integer>(), UINT64_MAX);
    XCTAssertEqual(sint64_value.get<yas::db::integer>(), INT64_MAX);
}

- (void)test_create_real_value {
    yas::db::value value{yas::db::real::type(1.0)};
    XCTAssertTrue(value.type() == typeid(yas::db::real));
    XCTAssertEqual(value.get<yas::db::real>(), 1.0);

    XCTAssertEqual(value.get<yas::db::integer>(), 0);
}

- (void)test_create_every_real_value {
    yas::db::value float32_value{Float32{1.0f}};
    yas::db::value float64_value{Float64{2.0}};

    XCTAssertTrue(float32_value.type() == typeid(yas::db::real));
    XCTAssertTrue(float64_value.type() == typeid(yas::db::real));

    XCTAssertEqual(float32_value.get<yas::db::real>(), 1.0f);
    XCTAssertEqual(float64_value.get<yas::db::real>(), 2.0);
}

- (void)test_create_text_value {
    yas::db::value value{yas::db::text::type("test")};
    XCTAssertTrue(value.type() == typeid(yas::db::text));
    XCTAssertEqual(value.get<yas::db::text>(), "test");

    XCTAssertEqual(value.get<yas::db::real>(), 0.0);
    XCTAssertEqual(value.get<yas::db::integer>(), 0);
}

- (void)test_create_blob_value_from_vector {
    std::vector<UInt8> vec{0, 1, 2, 3};
    yas::db::value value{vec.data(), static_cast<size_t>(vec.size())};
    XCTAssertTrue(value.type() == typeid(yas::db::blob));

    auto const &blob = value.get<yas::db::blob>();

    XCTAssertEqual(blob.size(), 4);

    const UInt8 *ptr = (const UInt8 *)(blob.data());
    XCTAssertEqual(ptr[0], 0);
    XCTAssertEqual(ptr[1], 1);
    XCTAssertEqual(ptr[2], 2);
    XCTAssertEqual(ptr[3], 3);
}

- (void)test_create_blob_value_from_ptr {
    std::vector<UInt8> vec{5, 6, 7};
    yas::db::value value{vec.data(), vec.size()};

    auto const &blob = value.get<yas::db::blob>();

    XCTAssertEqual(blob.size(), 3);

    UInt8 *ptr = (UInt8 *)(blob.data());
    XCTAssertEqual(ptr[0], 5);
    XCTAssertEqual(ptr[1], 6);
    XCTAssertEqual(ptr[2], 7);
}

- (void)test_create_null_value {
    yas::db::value value{nullptr};
    XCTAssertTrue(value.type() == typeid(yas::db::null));
    XCTAssertEqual(value.get<yas::db::null>(), nullptr);
}

- (void)test_no_copy {
    std::vector<UInt8> vec{10};
    yas::db::value value{vec.data(), vec.size(), yas::db::no_copy_tag};
}

- (void)test_move_assignment {
    yas::db::value value_a{yas::db::integer::type{5}};
    yas::db::value value_b{yas::db::integer::type{10}};

    XCTAssertEqual(value_a.get<yas::db::integer>(), 5);
    XCTAssertEqual(value_b.get<yas::db::integer>(), 10);

    value_b = std::move(value_a);

    XCTAssertEqual(value_b.get<yas::db::integer>(), 5);
}

- (void)test_create_empty_blob {
    yas::db::blob empty_blob{};
    XCTAssertEqual(empty_blob.data(), nullptr);
    XCTAssertEqual(empty_blob.size(), 0);
}

- (void)test_to_string {
    yas::db::value integer_value{yas::db::integer::type{8}};
    yas::db::value real_value{yas::db::real::type{0.5}};
    yas::db::value text_value{yas::db::text::type{"text_value"}};
    std::vector<UInt8> vec{0, 1};
    yas::db::value blob_value{yas::db::blob{vec.data(), vec.size()}};
    yas::db::value null_value{nullptr};

    XCTAssertEqual(yas::to_string(integer_value), "type='integer' value='8'");
    XCTAssertEqual(yas::to_string(real_value), "type='real' value='0.500000'");
    XCTAssertEqual(yas::to_string(text_value), "type='text' value='text_value'");
    XCTAssertEqual(yas::to_string(blob_value), "type='blob' value='data' size='2'");
    XCTAssertEqual(yas::to_string(null_value), "type='null' value='null'");
}

@end
