//
//  yas_db_value_tests.mm
//

#import <chrono>
#import "yas_db_test_utils.h"

using namespace yas;

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
    db::value value{db::integer::type(1)};
    XCTAssertTrue(value.type() == typeid(db::integer));
    XCTAssertEqual(value.get<db::integer>(), 1);

    XCTAssertEqual(value.get<db::real>(), 0.0);
    XCTAssertEqual(value.get<db::text>(), std::string{});
}

- (void)test_create_every_integer_value {
#warning todo numeric_limitsにする
    db::value bool_value{true};
    db::value uint8_value{uint8_t{UINT8_MAX}};
    db::value sint8_value{int8_t{INT8_MAX}};
    db::value uint16_value{uint16_t{UINT16_MAX}};
    db::value sint16_value{int16_t{INT16_MAX}};
    db::value uint32_value{uint32_t{UINT32_MAX}};
    db::value sint32_value{int32_t{INT32_MAX}};
    db::value uint64_value{uint64_t{UINT64_MAX}};
    db::value sint64_value{int64_t{INT64_MAX}};

    XCTAssertTrue(bool_value.type() == typeid(db::integer));
    XCTAssertTrue(uint8_value.type() == typeid(db::integer));
    XCTAssertTrue(sint8_value.type() == typeid(db::integer));
    XCTAssertTrue(uint16_value.type() == typeid(db::integer));
    XCTAssertTrue(sint16_value.type() == typeid(db::integer));
    XCTAssertTrue(uint32_value.type() == typeid(db::integer));
    XCTAssertTrue(sint32_value.type() == typeid(db::integer));
    XCTAssertTrue(uint64_value.type() == typeid(db::integer));
    XCTAssertTrue(sint64_value.type() == typeid(db::integer));

    XCTAssertEqual(bool_value.get<db::integer>(), true);
    XCTAssertEqual(uint8_value.get<db::integer>(), UINT8_MAX);
    XCTAssertEqual(sint8_value.get<db::integer>(), INT8_MAX);
    XCTAssertEqual(uint16_value.get<db::integer>(), UINT16_MAX);
    XCTAssertEqual(sint16_value.get<db::integer>(), INT16_MAX);
    XCTAssertEqual(uint32_value.get<db::integer>(), UINT32_MAX);
    XCTAssertEqual(sint32_value.get<db::integer>(), INT32_MAX);
    XCTAssertEqual(uint64_value.get<db::integer>(), UINT64_MAX);
    XCTAssertEqual(sint64_value.get<db::integer>(), INT64_MAX);
}

- (void)test_create_real_value {
    db::value value{db::real::type(1.0)};
    XCTAssertTrue(value.type() == typeid(db::real));
    XCTAssertEqual(value.get<db::real>(), 1.0);

    XCTAssertEqual(value.get<db::integer>(), 0);
}

- (void)test_create_every_real_value {
    db::value float32_value{Float32{1.0f}};
    db::value float64_value{Float64{2.0}};

    XCTAssertTrue(float32_value.type() == typeid(db::real));
    XCTAssertTrue(float64_value.type() == typeid(db::real));

    XCTAssertEqual(float32_value.get<db::real>(), 1.0f);
    XCTAssertEqual(float64_value.get<db::real>(), 2.0);
}

- (void)test_create_text_value {
    db::value value{db::text::type("test")};
    XCTAssertTrue(value.type() == typeid(db::text));
    XCTAssertEqual(value.get<db::text>(), "test");

    XCTAssertEqual(value.get<db::real>(), 0.0);
    XCTAssertEqual(value.get<db::integer>(), 0);
}

- (void)test_create_blob_value_from_vector {
    std::vector<uint8_t> vec{0, 1, 2, 3};
    db::value value{vec.data(), static_cast<std::size_t>(vec.size())};
    XCTAssertTrue(value.type() == typeid(db::blob));

    auto const &blob = value.get<db::blob>();

    XCTAssertEqual(blob.size(), 4);

    const uint8_t *ptr = (const uint8_t *)(blob.data());
    XCTAssertEqual(ptr[0], 0);
    XCTAssertEqual(ptr[1], 1);
    XCTAssertEqual(ptr[2], 2);
    XCTAssertEqual(ptr[3], 3);
}

- (void)test_create_blob_value_from_ptr {
    std::vector<uint8_t> vec{5, 6, 7};
    db::value value{vec.data(), vec.size()};

    auto const &blob = value.get<db::blob>();

    XCTAssertEqual(blob.size(), 3);

    uint8_t *ptr = (uint8_t *)(blob.data());
    XCTAssertEqual(ptr[0], 5);
    XCTAssertEqual(ptr[1], 6);
    XCTAssertEqual(ptr[2], 7);
}

- (void)test_create_null_value {
    db::value value{nullptr};
    XCTAssertTrue(value.type() == typeid(db::null));
    XCTAssertEqual(value.get<db::null>(), nullptr);
}

- (void)test_empty_value {
    db::value const &empty_value = db::value::null_value();
    XCTAssertFalse(empty_value);
}

- (void)test_no_copy {
    std::vector<uint8_t> vec{10};
    db::value value{vec.data(), vec.size(), yas::db::no_copy_tag};
}

- (void)test_move {
    db::value value_a{db::integer::type{5}};
    db::value value_b{db::integer::type{10}};

    XCTAssertEqual(value_a.get<db::integer>(), 5);
    XCTAssertEqual(value_b.get<db::integer>(), 10);

    value_b = std::move(value_a);

    XCTAssertTrue(value_b);
    XCTAssertEqual(value_b.get<db::integer>(), 5);
    XCTAssertFalse(value_a);

    db::value value_c = std::move(value_b);

    XCTAssertTrue(value_c);
    XCTAssertEqual(value_c.get<db::integer>(), 5);
    XCTAssertFalse(value_b);
}

- (void)test_create_empty_blob {
    db::blob empty_blob{};
    XCTAssertEqual(empty_blob.data(), nullptr);
    XCTAssertEqual(empty_blob.size(), 0);
}

- (void)test_sql {
    db::value integer_value{db::integer::type{12}};
    db::value real_value{db::real::type{2.5}};
    db::value text_value{db::text::type{"text_sql_value"}};
    db::value null_value{nullptr};

    XCTAssertEqual(integer_value.sql(), "12");
    XCTAssertEqual(real_value.sql(), "2.500000");
    XCTAssertEqual(text_value.sql(), "'text_sql_value'");
    XCTAssertEqual(null_value.sql(), "null");

    std::vector<uint8_t> vec{0};
    db::value blob_value{db::blob{vec.data(), vec.size()}};

    XCTAssertThrows(blob_value.sql());
}

- (void)test_to_string {
    db::value integer_value{db::integer::type{8}};
    db::value real_value{db::real::type{0.5}};
    db::value text_value{db::text::type{"text_value"}};
    std::vector<uint8_t> vec{0, 1};
    db::value blob_value{db::blob{vec.data(), vec.size()}};
    db::value null_value{nullptr};

    XCTAssertEqual(yas::to_string(integer_value), "8");
    XCTAssertEqual(yas::to_string(real_value), "0.500000");
    XCTAssertEqual(yas::to_string(text_value), "text_value");
    XCTAssertEqual(yas::to_string(blob_value), "");
    XCTAssertEqual(yas::to_string(null_value), "null");
}

- (void)test_is_equal_blobs {
    std::vector<uint8_t> vec_a{0, 1, 2, 3};
    std::vector<uint8_t> vec_a2{0, 1, 2, 3};
    std::vector<uint8_t> vec_b{0, 1, 2, 4};
    std::vector<uint8_t> vec_c{0, 1, 2};

    db::blob blob_a{vec_a.data(), vec_a.size()};
    db::blob blob_a2{vec_a2.data(), vec_a2.size()};
    db::blob blob_b{vec_b.data(), vec_b.size()};
    db::blob blob_c{vec_c.data(), vec_c.size()};
    db::blob blob_n;
    db::blob blob_n2;

    XCTAssertTrue(blob_a == blob_a);
    XCTAssertTrue(blob_a == blob_a2);
    XCTAssertFalse(blob_a == blob_b);
    XCTAssertFalse(blob_a == blob_c);
    XCTAssertTrue(blob_n == blob_n);
    XCTAssertTrue(blob_n2 == blob_n2);

    XCTAssertFalse(blob_a != blob_a);
    XCTAssertFalse(blob_a != blob_a2);
    XCTAssertTrue(blob_a != blob_b);
    XCTAssertTrue(blob_a != blob_c);
    XCTAssertFalse(blob_n != blob_n);
    XCTAssertFalse(blob_n2 != blob_n2);
}

- (void)test_is_equal_integer_values {
    db::value i_value_a{1};
    db::value i_value_b{1};
    db::value i_value_c{3};
    db::value t_value{"1"};

    XCTAssertTrue(i_value_a == i_value_a);
    XCTAssertTrue(i_value_a == i_value_b);
    XCTAssertFalse(i_value_a == i_value_c);
    XCTAssertFalse(i_value_a == t_value);

    XCTAssertFalse(i_value_a != i_value_a);
    XCTAssertFalse(i_value_a != i_value_b);
    XCTAssertTrue(i_value_a != i_value_c);
    XCTAssertTrue(i_value_a != t_value);
}

- (void)test_is_equal_real_values {
    db::value r_value_a{2.0};
    db::value r_value_b{2.0};
    db::value r_value_c{5.5};
    db::value t_value{"1"};

    XCTAssertTrue(r_value_a == r_value_a);
    XCTAssertTrue(r_value_a == r_value_b);
    XCTAssertFalse(r_value_a == r_value_c);
    XCTAssertFalse(r_value_a == t_value);

    XCTAssertFalse(r_value_a != r_value_a);
    XCTAssertFalse(r_value_a != r_value_b);
    XCTAssertTrue(r_value_a != r_value_c);
    XCTAssertTrue(r_value_a != t_value);
}

- (void)test_is_equal_text_values {
    db::value t_value_a{"aaa"};
    db::value t_value_b{"aaa"};
    db::value t_value_c{"bbb"};
    db::value i_value{1};

    XCTAssertTrue(t_value_a == t_value_a);
    XCTAssertTrue(t_value_a == t_value_b);
    XCTAssertFalse(t_value_a == t_value_c);
    XCTAssertFalse(t_value_a == i_value);

    XCTAssertFalse(t_value_a != t_value_a);
    XCTAssertFalse(t_value_a != t_value_b);
    XCTAssertTrue(t_value_a != t_value_c);
    XCTAssertTrue(t_value_a != i_value);
}

- (void)test_is_equal_blob_values {
    std::vector<uint8_t> vec_a{1};
    std::vector<uint8_t> vec_b{1};
    std::vector<uint8_t> vec_c{3};

    db::value b_value_a{vec_a.data(), vec_a.size()};
    db::value b_value_b{vec_b.data(), vec_b.size()};
    db::value b_value_c{vec_c.data(), vec_c.size()};
    db::value t_value{"1"};

    XCTAssertTrue(b_value_a == b_value_a);
    XCTAssertTrue(b_value_a == b_value_b);
    XCTAssertFalse(b_value_a == b_value_c);
    XCTAssertFalse(b_value_a == t_value);

    XCTAssertFalse(b_value_a != b_value_a);
    XCTAssertFalse(b_value_a != b_value_b);
    XCTAssertTrue(b_value_a != b_value_c);
    XCTAssertTrue(b_value_a != t_value);
}

- (void)test_is_equal_null_values {
    db::value n_value_a{nullptr};
    db::value n_value_b{nullptr};
    db::value t_value{"null"};

    XCTAssertTrue(n_value_a == n_value_a);
    XCTAssertTrue(n_value_a == n_value_b);
    XCTAssertFalse(n_value_a == t_value);

    XCTAssertFalse(n_value_a != n_value_a);
    XCTAssertFalse(n_value_a != n_value_b);
    XCTAssertTrue(n_value_a != t_value);
}

- (void)test_time_point {
    auto src_time_point = db::time_point{std::chrono::nanoseconds{1234}};

    XCTAssertEqual(src_time_point.time_since_epoch().count(), 1234);

    auto value = to_value(src_time_point);

    XCTAssertEqual(value.get<db::integer>(), 1234);

    auto dst_time_point = to_time_point(value);

    XCTAssertEqual(dst_time_point.time_since_epoch().count(), 1234);
}

- (void)test_cast {
    db::value value{"a"};
    base base_value = value;

    db::value casted_value = cast<db::value>(base_value);

    XCTAssertTrue(casted_value);
    XCTAssertEqual(casted_value, db::value{"a"});
}

@end
