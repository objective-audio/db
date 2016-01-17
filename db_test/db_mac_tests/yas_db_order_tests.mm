//
//  yas_db_order_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_order_tests : XCTestCase

@end

@implementation yas_db_order_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create_ascending {
    db::field_order order{"test_field_a", db::order::ascending};

    XCTAssertEqual(order.field, "test_field_a");
    XCTAssertEqual(order.order, db::order::ascending);
}

- (void)test_create_descending {
    db::field_order order{"test_field_d", db::order::descending};

    XCTAssertEqual(order.field, "test_field_d");
    XCTAssertEqual(order.order, db::order::descending);
}

- (void)test_sql {
    XCTAssertEqual((db::field_order{"test_field_a", db::order::ascending}.sql()), "test_field_a asc");
    XCTAssertEqual((db::field_order{"test_field_d", db::order::descending}.sql()), "test_field_d desc");
}

@end
