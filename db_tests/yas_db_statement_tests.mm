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
    auto statement = db::statement::make_shared();

    auto const closable_statement = db::closable::cast(statement);
    XCTAssertTrue(closable_statement);
}

- (void)test_stmt {
}

- (void)test_query {
    auto statement = db::statement::make_shared();

    XCTAssertEqual(statement->query(), "");

    statement->set_query("test_query");

    auto const &const_statement = statement;

    XCTAssertEqual(const_statement->query(), "test_query");
}

- (void)test_in_use {
    auto statement = db::statement::make_shared();

    XCTAssertFalse(statement->in_use());

    statement->set_in_use(true);

    auto const &const_statement = statement;

    XCTAssertTrue(const_statement->in_use());
}

- (void)test_reset {
    auto statement = db::statement::make_shared();

    statement->set_in_use(true);

    XCTAssertTrue(statement->in_use());

    statement->reset();

    XCTAssertFalse(statement->in_use());
}

@end
