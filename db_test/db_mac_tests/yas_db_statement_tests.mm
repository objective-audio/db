//
//  yas_db_statement_tests.mm
//

#import "yas_db_test_utils.h"

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
    yas::db::statement statement;

    auto closable_statement = dynamic_cast<yas::db::closable *>(&statement);
    XCTAssertTrue(closable_statement != nullptr);
}

- (void)test_stmt {
}

- (void)test_query {
    yas::db::statement statement;

    XCTAssertEqual(statement.query().value(), "");

    statement.query().set_value("test_query");

    auto const &const_statement = statement;

    XCTAssertEqual(const_statement.query().value(), "test_query");
}

- (void)test_in_use {
    yas::db::statement statement;

    XCTAssertFalse(statement.in_use().value());

    statement.in_use().set_value(true);

    auto const &const_statement = statement;

    XCTAssertTrue(const_statement.in_use().value());
}

- (void)test_reset {
    yas::db::statement statement;

    statement.in_use().set_value(true);

    XCTAssertTrue(statement.in_use().value());

    statement.reset();

    XCTAssertFalse(statement.in_use().value());
}

@end
