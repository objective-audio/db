//
//  yas_db_attribute_tests.mm
//

#import <XCTest/XCTest.h>
#import <iostream>
#import "yas_db_attribute.h"
#import "yas_db_additional_types.h"

using namespace yas;

@interface yas_db_attribute_tests : XCTestCase

@end

@implementation yas_db_attribute_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create_integer {
    db::attribute attr{
        {.name = "integer_attr", .type = db::attribute_type::integer, .default_value = db::value{1}, .not_null = true}};

    XCTAssertEqual(attr.name, "integer_attr");
    XCTAssertEqual(attr.type, "INTEGER");
    XCTAssertTrue(attr.default_value.type() == typeid(db::integer));
    XCTAssertEqual(attr.default_value.get<db::integer>(), 1);
    XCTAssertEqual(attr.not_null, true);
    XCTAssertEqual(attr.primary, false);
    XCTAssertEqual(attr.unique, false);
}

- (void)test_create_real {
    db::attribute attr{{.name = "real_attr", .type = db::attribute_type::real, .default_value = db::value{2.5}}};

    XCTAssertEqual(attr.name, "real_attr");
    XCTAssertEqual(attr.type, "REAL");
    XCTAssertTrue(attr.default_value.type() == typeid(db::real));
    XCTAssertEqual(attr.default_value.get<db::real>(), 2.5);
    XCTAssertEqual(attr.not_null, false);
    XCTAssertEqual(attr.primary, false);
    XCTAssertEqual(attr.unique, false);
}

- (void)test_create_text {
    db::attribute attr{
        {.name = "text_attr", .type = db::attribute_type::text, .default_value = db::value{"test_string"}}};

    XCTAssertEqual(attr.name, "text_attr");
    XCTAssertEqual(attr.type, "TEXT");
    XCTAssertTrue(attr.default_value.type() == typeid(db::text));
    XCTAssertEqual(attr.default_value.get<db::text>(), "test_string");
    XCTAssertEqual(attr.not_null, false);
    XCTAssertEqual(attr.primary, false);
    XCTAssertEqual(attr.unique, false);
}

- (void)test_create_blob {
    std::vector<uint8_t> vec{2, 4};
    db::attribute attr{
        {.name = "blob_attr", .type = db::attribute_type::blob, .default_value = db::value{vec.data(), vec.size()}}};

    XCTAssertEqual(attr.name, "blob_attr");
    XCTAssertEqual(attr.type, "BLOB");
    XCTAssertTrue(attr.default_value.type() == typeid(db::blob));

    auto &blob = attr.default_value.get<db::blob>();
    uint8_t const *data = static_cast<uint8_t const *>(blob.data());
    XCTAssertEqual(blob.size(), 2);
    XCTAssertEqual(data[0], 2);
    XCTAssertEqual(data[1], 4);

    XCTAssertEqual(attr.not_null, false);
    XCTAssertEqual(attr.primary, false);
    XCTAssertEqual(attr.unique, false);
}

- (void)test_create_id_attribute {
    auto const &attr = db::attribute::id_attribute();

    XCTAssertEqual(attr.name, "pk_id");
    XCTAssertEqual(attr.type, "INTEGER");
    XCTAssertTrue(attr.default_value.type() == typeid(db::null));
    XCTAssertEqual(attr.not_null, false);
    XCTAssertEqual(attr.primary, true);
}

- (void)test_create_invalid_name {
    XCTAssertThrows(
        (db::attribute{{.name = "", .type = db::attribute_type::text, .default_value = db::value{"test_string"}}}));
}

- (void)test_create_invalid_value_type {
    XCTAssertThrows(
        (db::attribute{{.name = "test_name", .type = db::attribute_type::integer, db::value{"test_value"}}}));
    XCTAssertThrows((db::attribute{{.name = "test_name", .type = db::attribute_type::real, db::value{"test_value"}}}));
    XCTAssertThrows((db::attribute{{.name = "test_name", .type = db::attribute_type::text, db::value{2}}}));
    XCTAssertThrows((db::attribute{{.name = "test_name", .type = db::attribute_type::blob, db::value{3}}}));
}

- (void)test_sql {
    db::attribute attr{{.name = "test_name",
                        .type = db::attribute_type::text,
                        .default_value = db::value{"test_string"},
                        .not_null = true}};

    XCTAssertEqual(attr.sql(), "test_name TEXT NOT NULL DEFAULT 'test_string'");
}

- (void)test_sql_without_options {
    db::attribute attr{{.name = "test_name", .type = db::attribute_type::text, .not_null = false}};

    XCTAssertEqual(attr.sql(), "test_name TEXT");
}

- (void)test_id_sql {
    auto const &attr = db::attribute::id_attribute();

    XCTAssertEqual(attr.sql(), "pk_id INTEGER PRIMARY KEY AUTOINCREMENT");
}

- (void)test_full_sql {
    db::attribute attr{{"test_name", db::attribute_type::integer, db::value{5}, true, true, true}};

    XCTAssertEqual(attr.sql(), "test_name INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE NOT NULL DEFAULT 5");
}

@end
