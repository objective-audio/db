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
    NSDictionary *dict = @{ @"type": @"integer", @"default": @(1), @"not_null": @YES };

    db::attribute attr{"integer_attr", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(attr.name, "integer_attr");
    XCTAssertEqual(attr.type, "integer");
    XCTAssertTrue(attr.default_value.type() == typeid(db::integer));
    XCTAssertEqual(attr.default_value.get<db::integer>(), 1);
    XCTAssertEqual(attr.not_null, true);
    XCTAssertEqual(attr.primary, false);
    XCTAssertEqual(attr.unique, false);
}

- (void)test_create_real {
    NSDictionary *dict = @{ @"type": @"real", @"default": @(2.5) };

    db::attribute attr{"real_attr", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(attr.name, "real_attr");
    XCTAssertEqual(attr.type, "real");
    XCTAssertTrue(attr.default_value.type() == typeid(db::real));
    XCTAssertEqual(attr.default_value.get<db::real>(), 2.5);
    XCTAssertEqual(attr.not_null, false);
    XCTAssertEqual(attr.primary, false);
    XCTAssertEqual(attr.unique, false);
}

- (void)test_create_text {
    NSDictionary *dict = @{ @"type": @"text", @"default": @"test_string" };

    db::attribute attr{"text_attr", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(attr.name, "text_attr");
    XCTAssertEqual(attr.type, "text");
    XCTAssertTrue(attr.default_value.type() == typeid(db::text));
    XCTAssertEqual(attr.default_value.get<db::text>(), "test_string");
    XCTAssertEqual(attr.not_null, false);
    XCTAssertEqual(attr.primary, false);
    XCTAssertEqual(attr.unique, false);
}

- (void)test_create_blob {
    std::vector<UInt8> vec{2, 4};
    NSDictionary *dict = @{ @"type": @"blob", @"default": [NSData dataWithBytes:vec.data() length:vec.size()] };

    db::attribute attr{"blob_attr", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(attr.name, "blob_attr");
    XCTAssertEqual(attr.type, "blob");
    XCTAssertTrue(attr.default_value.type() == typeid(db::blob));

    auto &blob = attr.default_value.get<db::blob>();
    UInt8 const *data = static_cast<UInt8 const *>(blob.data());
    XCTAssertEqual(blob.size(), 2);
    XCTAssertEqual(data[0], 2);
    XCTAssertEqual(data[1], 4);

    XCTAssertEqual(attr.not_null, false);
    XCTAssertEqual(attr.primary, false);
    XCTAssertEqual(attr.unique, false);
}

- (void)test_create_id_attribute {
    auto attr = db::attribute::id_attribute();

    XCTAssertEqual(attr.name, "id");
    XCTAssertEqual(attr.type, "integer");
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

    dict = @{ @"type": @"integer", @"default": @"test_value" };
    XCTAssertThrows(db::attribute("test_name", (__bridge CFDictionaryRef)dict));

    dict = @{ @"type": @"real", @"default": @"test_value" };
    XCTAssertThrows(db::attribute("test_name", (__bridge CFDictionaryRef)dict));

    dict = @{ @"type": @"text", @"default": @(2) };
    XCTAssertThrows(db::attribute("test_name", (__bridge CFDictionaryRef)dict));

    dict = @{ @"type": @"blob", @"default": @(3) };
    XCTAssertThrows(db::attribute("test_name", (__bridge CFDictionaryRef)dict));
}

- (void)test_sql {
    NSDictionary *dict = @{ @"type": @"text", @"default": @"test_string", @"not_null": @YES };
    db::attribute attr{"test_name", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(attr.sql(), "test_name text not null default 'test_string'");
}

- (void)test_sql_without_options {
    NSDictionary *dict = @{ @"type": @"text", @"not_null": @NO };
    db::attribute attr{"test_name", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(attr.sql(), "test_name text");
}

- (void)test_id_sql {
    auto attr = db::attribute::id_attribute();

    XCTAssertEqual(attr.sql(), "id integer primary key");
}

- (void)test_full_sql {
    db::attribute attr{"test_name", db::integer::name, db::value{5}, true, true, true};

    XCTAssertEqual(attr.sql(), "test_name integer primary key unique not null default 5");
}

@end
