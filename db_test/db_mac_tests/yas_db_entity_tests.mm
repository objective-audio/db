//
//  yas_db_entity_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_entity_tests : XCTestCase

@end

@implementation yas_db_entity_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_create {
    NSDictionary *attr_dict = @{ @"type": @"integer", @"default": @1 };
    db::attribute attr{"attr_name", (__bridge CFDictionaryRef)attr_dict};
    NSDictionary *rel_dict = @{ @"target": @"test_target" };
    db::relation rel{"entity_name", "rel_name", (__bridge CFDictionaryRef)rel_dict};

    db::entity entity{"entity_name", {{attr.name, std::move(attr)}}, {{rel.name, std::move(rel)}}};

    XCTAssertEqual(entity.name, "entity_name");
    XCTAssertEqual(entity.attributes.size(), 1);
    XCTAssertEqual(entity.relations.size(), 1);

    XCTAssertEqual(entity.sql(), "create table if not exists entity_name (attr_name integer default 1);");
}

@end
