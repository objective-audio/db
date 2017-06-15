//
//  yas_db_relation_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_relation_tests : XCTestCase

@end

@implementation yas_db_relation_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create {
    NSDictionary *dict = @{ @"target": @"test_target", @"many": @YES };
    db::relation relation{"test_entity", "test_name", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(relation.source_entity_name, "test_entity");
    XCTAssertEqual(relation.name, "test_name");
    XCTAssertEqual(relation.target_entity_name, "test_target");
    XCTAssertEqual(relation.many, true);
}

- (void)test_table_name {
    NSDictionary *dict = @{ @"target": @"test_target" };
    db::relation relation{"test_entity", "test_name", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(relation.table_name, "rel_test_entity_test_name");
}

- (void)test_sql {
    NSDictionary *dict = @{ @"target": @"c" };
    db::relation relation{"a", "b", (__bridge CFDictionaryRef)dict};

    XCTAssertEqual(relation.sql_for_create(),
                   "CREATE TABLE IF NOT EXISTS rel_a_b (pk_id INTEGER PRIMARY KEY AUTOINCREMENT, src_pk_id INTEGER, "
                   "src_obj_id INTEGER, "
                   "tgt_obj_id INTEGER, "
                   "save_id INTEGER);");
}

@end
