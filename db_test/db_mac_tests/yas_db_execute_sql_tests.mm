//
//  yas_db_execute_sql_tests.mm
//

#import "yas_db_test_utils.h"

@interface yas_db_execute_sql_tests : XCTestCase

@end

@implementation yas_db_execute_sql_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_table {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    std::string const &create_sql_a = yas::db::create_table_sql("test_table_a", {"field_a"});
    XCTAssertTrue(db.execute_update(create_sql_a));

    std::string const &create_sql_b = yas::db::create_table_sql("test_table_b", {"field_b"});
    XCTAssertTrue(db.execute_update(create_sql_b));

    XCTAssertTrue(db.table_exists("test_table_a"));
    XCTAssertTrue(db.table_exists("test_table_b"));

    auto schema_set_1 = db.get_table_schema("test_table_a");
    XCTAssertTrue(schema_set_1.next());
    XCTAssertEqual(schema_set_1.column_value("name").value<yas::db::text>(), "field_a");
    XCTAssertFalse(schema_set_1.next());

    std::string const &alter_sql = yas::db::alter_table_sql("test_table_a", "field_c");
    XCTAssertTrue(db.execute_update(alter_sql));

    auto schema_set_2 = db.get_table_schema("test_table_a");
    XCTAssertTrue(schema_set_2.next());
    XCTAssertEqual(schema_set_2.column_value("name").value<yas::db::text>(), "field_a");
    XCTAssertTrue(schema_set_2.next());
    XCTAssertEqual(schema_set_2.column_value("name").value<yas::db::text>(), "field_c");
    XCTAssertFalse(schema_set_2.next());

    std::string const &drop_sql = yas::db::drop_table_sql("test_table_b");
    XCTAssertTrue(db.execute_update(drop_sql));

    XCTAssertTrue(db.table_exists("test_table_a"));
    XCTAssertFalse(db.table_exists("test_table_b"));
}

@end
