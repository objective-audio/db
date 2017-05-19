//
//  yas_db_attribute_tests.mm
//

#import <XCTest/XCTest.h>
#import <iostream>
#import "yas_db_attribute.h"

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
    NSDictionary *dict = @{ @"type": @"INTEGER", @"default": @(1), @"not_null": @YES };

    db::attribute attr{"integer_attr", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(attr.name, "integer_attr");
    XCTAssertEqual(attr.type, "INTEGER");
    XCTAssertTrue(attr.default_value.type() == typeid(db::integer));
    XCTAssertEqual(attr.default_value.get<db::integer>(), 1);
    XCTAssertEqual(attr.not_null, true);
    XCTAssertEqual(attr.primary, false);
    XCTAssertEqual(attr.unique, false);
}

- (void)test_create_real {
    NSDictionary *dict = @{ @"type": @"REAL", @"default": @(2.5) };

    db::attribute attr{"real_attr", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(attr.name, "real_attr");
    XCTAssertEqual(attr.type, "REAL");
    XCTAssertTrue(attr.default_value.type() == typeid(db::real));
    XCTAssertEqual(attr.default_value.get<db::real>(), 2.5);
    XCTAssertEqual(attr.not_null, false);
    XCTAssertEqual(attr.primary, false);
    XCTAssertEqual(attr.unique, false);
}

- (void)test_create_text {
    NSDictionary *dict = @{ @"type": @"TEXT", @"default": @"test_string" };

    db::attribute attr{"text_attr", (__bridge CFDictionaryRef)dict};

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
    NSDictionary *dict = @{ @"type": @"BLOB", @"default": [NSData dataWithBytes:vec.data() length:vec.size()] };

    db::attribute attr{"blob_attr", (__bridge CFDictionaryRef)dict};

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
    NSDictionary *dict = @{ @"type": @"text", @"default": @"test_string" };
    XCTAssertThrows(db::attribute(std::string(), (__bridge CFDictionaryRef)dict));
}

- (void)test_create_invalid_type {
    NSDictionary *dict = @{ @"type": @"hoge", @"default": @"test_string" };
    XCTAssertThrows(db::attribute("test_name", (__bridge CFDictionaryRef)dict));
}

- (void)test_create_invalid_not_null {
    NSDictionary *dict = @{ @"type": @"integer", @"default": [NSNull null], @"not_null": @YES };

    XCTAssertThrows(db::attribute("integer_attr", (__bridge CFDictionaryRef)dict));
}

- (void)test_create_invalid_value_type {
    NSDictionary *dict;

    dict = @{ @"type": @"INTEGER", @"default": @"test_value" };
    XCTAssertThrows(db::attribute("test_name", (__bridge CFDictionaryRef)dict));

    dict = @{ @"type": @"REAL", @"default": @"test_value" };
    XCTAssertThrows(db::attribute("test_name", (__bridge CFDictionaryRef)dict));

    dict = @{ @"type": @"TEXT", @"default": @(2) };
    XCTAssertThrows(db::attribute("test_name", (__bridge CFDictionaryRef)dict));

    dict = @{ @"type": @"BLOB", @"default": @(3) };
    XCTAssertThrows(db::attribute("test_name", (__bridge CFDictionaryRef)dict));
}

- (void)test_sql {
    NSDictionary *dict = @{ @"type": @"TEXT", @"default": @"test_string", @"not_null": @YES };
    db::attribute attr{"test_name", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(attr.sql(), "test_name TEXT NOT NULL DEFAULT 'test_string'");
}

- (void)test_sql_without_options {
    NSDictionary *dict = @{ @"type": @"TEXT", @"not_null": @NO };
    db::attribute attr{"test_name", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(attr.sql(), "test_name TEXT");
}

- (void)test_id_sql {
    auto const &attr = db::attribute::id_attribute();

    XCTAssertEqual(attr.sql(), "pk_id INTEGER PRIMARY KEY AUTOINCREMENT");
}

- (void)test_full_sql {
    db::attribute attr{"test_name", db::integer::name, db::value{5}, true, true, true};

    XCTAssertEqual(attr.sql(), "test_name INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE NOT NULL DEFAULT 5");
}

@end
