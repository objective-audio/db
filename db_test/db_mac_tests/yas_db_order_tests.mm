//
//  yas_db_order_tests.mm
//

#import "yas_db_test_utils.h"

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
    yas::db::field_order order{"test_field_a", yas::db::order::ascending};

    XCTAssertEqual(order.field, "test_field_a");
    XCTAssertEqual(order.order, yas::db::order::ascending);
}

- (void)test_create_descending {
    yas::db::field_order order{"test_field_d", yas::db::order::descending};

    XCTAssertEqual(order.field, "test_field_d");
    XCTAssertEqual(order.order, yas::db::order::descending);
}

@end
