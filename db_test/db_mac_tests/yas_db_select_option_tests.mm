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

- (void)test_range_sql {
    db::range range{.location = 1, .length = 2};
    XCTAssertEqual(range.sql(), "1, 2");
}

- (void)test_range_is_empty {
    XCTAssertTrue(db::empty_range().is_empty());
    XCTAssertFalse((db::range{.location = 1, .length = 2}).is_empty());
}

@end
