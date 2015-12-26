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
    yas::db::column_value value{sqlite3_int64(1)};
    XCTAssertEqual(value.type(), yas::db::value_type::int64);
    XCTAssertEqual(value.value<yas::db::int64>(), 1);

    XCTAssertEqual(value.value<yas::db::float64>(), 0.0);
    XCTAssertEqual(value.value<yas::db::string>(), std::string{});
}

- (void)test_create_float_value {
    yas::db::column_value value{1.0};
    XCTAssertEqual(value.type(), yas::db::value_type::float64);
    XCTAssertEqual(value.value<yas::db::float64>(), 1.0);

    XCTAssertEqual(value.value<yas::db::int64>(), 0);
}

- (void)test_create_string_value {
    yas::db::column_value value{"test"};
    XCTAssertEqual(value.type(), yas::db::value_type::string);
    XCTAssertEqual(value.value<yas::db::string>(), "test");

    XCTAssertEqual(value.value<yas::db::float64>(), 0.0);
    XCTAssertEqual(value.value<yas::db::int64>(), 0);
}

- (void)test_create_blob_value_from_vector {
    std::vector<UInt8> vec{0, 1, 2, 3};
    yas::db::column_value value{vec.data(), static_cast<size_t>(vec.size())};
    XCTAssertEqual(value.type(), yas::db::value_type::blob);

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
    XCTAssertEqual(value.type(), yas::db::value_type::null);
    XCTAssertEqual(value.value<yas::db::null>(), nullptr);
}

- (void)test_no_copy {
    std::vector<UInt8> vec{10};
    yas::db::column_value value{vec.data(), vec.size(), yas::db::no_copy_tag};
}

@end
