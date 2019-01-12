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
    db::relation relation{{.name = "test_name", .target = "test_target", .many = true}, "test_entity"};

    XCTAssertEqual(relation.source, "test_entity");
    XCTAssertEqual(relation.name, "test_name");
    XCTAssertEqual(relation.target, "test_target");
    XCTAssertEqual(relation.many, true);
}

- (void)test_table_name {
    db::relation relation{{.name = "test_name", .target = "test_target", .many = true}, "test_entity"};

    XCTAssertEqual(relation.table, "rel_test_entity_test_name");
}

- (void)test_sql {
    db::relation relation{{.name = "b", .target = "c", .many = true}, "a"};

    XCTAssertEqual(relation.sql_for_create(),
                   "CREATE TABLE IF NOT EXISTS rel_a_b (pk_id INTEGER PRIMARY KEY AUTOINCREMENT, src_pk_id INTEGER, "
                   "src_obj_id INTEGER, "
                   "tgt_obj_id INTEGER, "
                   "save_id INTEGER);");
}

@end
