//
//  yas_db_select_option_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_select_option_tests : XCTestCase

@end

@implementation yas_db_select_option_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_field_order_ascending_sql {
    db::field_order order{.field = "a", .order = db::order::ascending};
    XCTAssertEqual(order.sql(), "a ASC");
}

- (void)test_field_order_descending_sql {
    db::field_order order{.field = "b", .order = db::order::descending};
    XCTAssertEqual(order.sql(), "b DESC");
}

@end
