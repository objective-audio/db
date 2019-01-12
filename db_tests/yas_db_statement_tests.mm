//
//  yas_db_statement_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_statement_tests : XCTestCase

@end

@implementation yas_db_statement_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_closable {
    db::statement statement;

    auto closable_statement = statement.closable();
    XCTAssertTrue(closable_statement);
}

- (void)test_stmt {
}

- (void)test_query {
    db::statement statement;

    XCTAssertEqual(statement.query(), "");

    statement.set_query("test_query");

    auto const &const_statement = statement;

    XCTAssertEqual(const_statement.query(), "test_query");
}

- (void)test_in_use {
    db::statement statement;

    XCTAssertFalse(statement.in_use());

    statement.set_in_use(true);

    auto const &const_statement = statement;

    XCTAssertTrue(const_statement.in_use());
}

- (void)test_reset {
    db::statement statement;

    statement.set_in_use(true);

    XCTAssertTrue(statement.in_use());

    statement.reset();

    XCTAssertFalse(statement.in_use());
}

@end
