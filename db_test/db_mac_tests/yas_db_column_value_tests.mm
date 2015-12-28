//
//  yas_db_column_value_tests.mm
//

#import "yas_db_test_utils.h"

@interface yas_db_column_value_tests : XCTestCase

@end

@implementation yas_db_column_value_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create_int_value {
    yas::db::column_value value{yas::db::int64::type(1)};
    XCTAssertTrue(value.type() == typeid(yas::db::int64));
    XCTAssertEqual(value.value<yas::db::int64>(), 1);

    XCTAssertEqual(value.value<yas::db::float64>(), 0.0);
    XCTAssertEqual(value.value<yas::db::string>(), std::string{});
}

- (void)test_create_every_int_value {
    yas::db::column_value uint8_value{UInt8{UINT8_MAX}};
    yas::db::column_value sint8_value{SInt8{INT8_MAX}};
    yas::db::column_value uint16_value{UInt16{UINT16_MAX}};
    yas::db::column_value sint16_value{SInt16{INT16_MAX}};
    yas::db::column_value uint32_value{UInt32{UINT32_MAX}};
    yas::db::column_value sint32_value{SInt32{INT32_MAX}};
    yas::db::column_value uint64_value{UInt64{UINT64_MAX}};
    yas::db::column_value sint64_value{SInt64{INT64_MAX}};

    XCTAssertTrue(uint8_value.type() == typeid(yas::db::int64));
    XCTAssertTrue(sint8_value.type() == typeid(yas::db::int64));
    XCTAssertTrue(uint16_value.type() == typeid(yas::db::int64));
    XCTAssertTrue(sint16_value.type() == typeid(yas::db::int64));
    XCTAssertTrue(uint32_value.type() == typeid(yas::db::int64));
    XCTAssertTrue(sint32_value.type() == typeid(yas::db::int64));
    XCTAssertTrue(uint64_value.type() == typeid(yas::db::int64));
    XCTAssertTrue(sint64_value.type() == typeid(yas::db::int64));

    XCTAssertEqual(uint8_value.value<yas::db::int64>(), UINT8_MAX);
    XCTAssertEqual(sint8_value.value<yas::db::int64>(), INT8_MAX);
    XCTAssertEqual(uint16_value.value<yas::db::int64>(), UINT16_MAX);
    XCTAssertEqual(sint16_value.value<yas::db::int64>(), INT16_MAX);
    XCTAssertEqual(uint32_value.value<yas::db::int64>(), UINT32_MAX);
    XCTAssertEqual(sint32_value.value<yas::db::int64>(), INT32_MAX);
    XCTAssertEqual(uint64_value.value<yas::db::int64>(), UINT64_MAX);
    XCTAssertEqual(sint64_value.value<yas::db::int64>(), INT64_MAX);
}

- (void)test_create_float_value {
    yas::db::column_value value{yas::db::float64::type(1.0)};
    XCTAssertTrue(value.type() == typeid(yas::db::float64));
    XCTAssertEqual(value.value<yas::db::float64>(), 1.0);

    XCTAssertEqual(value.value<yas::db::int64>(), 0);
}

- (void)test_create_every_float_value {
    yas::db::column_value float32_value{Float32{1.0f}};
    yas::db::column_value float64_value{Float64{2.0}};

    XCTAssertTrue(float32_value.type() == typeid(yas::db::float64));
    XCTAssertTrue(float64_value.type() == typeid(yas::db::float64));

    XCTAssertEqual(float32_value.value<yas::db::float64>(), 1.0f);
    XCTAssertEqual(float64_value.value<yas::db::float64>(), 2.0);
}

- (void)test_create_string_value {
    yas::db::column_value value{yas::db::string::type("test")};
    XCTAssertTrue(value.type() == typeid(yas::db::string));
    XCTAssertEqual(value.value<yas::db::string>(), "test");

    XCTAssertEqual(value.value<yas::db::float64>(), 0.0);
    XCTAssertEqual(value.value<yas::db::int64>(), 0);
}

- (void)test_create_blob_value_from_vector {
    std::vector<UInt8> vec{0, 1, 2, 3};
    yas::db::column_value value{vec.data(), static_cast<size_t>(vec.size())};
    XCTAssertTrue(value.type() == typeid(yas::db::blob));

    auto const &blob = value.value<yas::db::blob>();

    XCTAssertEqual(blob.size(), 4);

    const UInt8 *ptr = (const UInt8 *)(blob.data());
    XCTAssertEqual(ptr[0], 0);
    XCTAssertEqual(ptr[1], 1);
    XCTAssertEqual(ptr[2], 2);
    XCTAssertEqual(ptr[3], 3);
}

- (void)test_create_blob_value_from_ptr {
    std::vector<UInt8> vec{5, 6, 7};
    yas::db::column_value value{vec.data(), vec.size()};

    auto const &blob = value.value<yas::db::blob>();

    XCTAssertEqual(blob.size(), 3);

    UInt8 *ptr = (UInt8 *)(blob.data());
    XCTAssertEqual(ptr[0], 5);
    XCTAssertEqual(ptr[1], 6);
    XCTAssertEqual(ptr[2], 7);
}

- (void)test_create_null_value {
    yas::db::column_value value{nullptr};
    XCTAssertTrue(value.type() == typeid(yas::db::null));
    XCTAssertEqual(value.value<yas::db::null>(), nullptr);
}

- (void)test_no_copy {
    std::vector<UInt8> vec{10};
    yas::db::column_value value{vec.data(), vec.size(), yas::db::no_copy_tag};
}

- (void)test_move_assignment {
    yas::db::column_value value_a{yas::db::int64::type{5}};
    yas::db::column_value value_b{yas::db::int64::type{10}};

    XCTAssertEqual(value_a.value<yas::db::int64>(), 5);
    XCTAssertEqual(value_b.value<yas::db::int64>(), 10);

    value_b = std::move(value_a);

    XCTAssertEqual(value_b.value<yas::db::int64>(), 5);
}

- (void)test_create_empty_blob {
    yas::db::blob empty_blob{};
    XCTAssertEqual(empty_blob.data(), nullptr);
    XCTAssertEqual(empty_blob.size(), 0);
}

- (void)test_to_string {
    yas::db::column_value int_value{yas::db::int64::type{8}};
    yas::db::column_value float_value{yas::db::float64::type{0.5}};
    yas::db::column_value string_value{yas::db::string::type{"string_value"}};
    std::vector<UInt8> vec{0, 1};
    yas::db::column_value blob_value{yas::db::blob{vec.data(), vec.size()}};
    yas::db::column_value null_value{nullptr};

    XCTAssertEqual(yas::to_string(int_value), "type='int64' value='8'");
    XCTAssertEqual(yas::to_string(float_value), "type='float64' value='0.500000'");
    XCTAssertEqual(yas::to_string(string_value), "type='string' value='string_value'");
    XCTAssertEqual(yas::to_string(blob_value), "type='blob' value='data' size='2'");
    XCTAssertEqual(yas::to_string(null_value), "type='null' value='null'");
}

@end
