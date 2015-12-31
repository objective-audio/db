//
//  yas_db_manager_tests.mm
//

#import "yas_db_test_utils.h"

@interface yas_db_manager_tests : XCTestCase

@end

@implementation yas_db_manager_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_create {
    auto db_path = [yas_db_test_utils database_path];
    yas::db::manager manager{db_path};

    XCTAssertTrue(manager);
    XCTAssertEqual(manager.database_path(), db_path);
}

- (void)test_execute_in_bg {
    auto manager = [yas_db_test_utils create_test_manager];

    XCTestExpectation *expectation = [self expectationWithDescription:@"execution"];

    manager.execute([self, expectation](auto &database, auto const &operation) {
        XCTAssertTrue(database);
        XCTAssertTrue(operation);
        XCTAssertFalse([NSThread isMainThread]);
        [expectation fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_execute_update_and_query_in_bg {
    auto manager = [yas_db_test_utils create_test_manager];

    XCTestExpectation *expectation = [self expectationWithDescription:@"execution"];

    manager.execute([self, expectation](yas::db::database &db, auto const &operation) {
        XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"field_a", "field_b"})));

        yas::db::column_vector args{yas::db::value{"value_a"}, yas::db::value{"value_b"}};
        XCTAssertTrue(db.execute_update("insert into test_table(field_a, field_b) values(:field_a, :field_b)", args));

        auto query_result = db.execute_query("select * from test_table");
        auto &result_set = query_result.value();

        XCTAssertTrue(result_set);
        XCTAssertTrue(result_set.next());

        XCTAssertEqual(result_set.column_value(0).get<yas::db::text>(), "value_a");
        XCTAssertEqual(result_set.column_value(1).get<yas::db::text>(), "value_b");

        XCTAssertFalse(result_set.next());

        [expectation fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

@end
