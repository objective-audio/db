//
//  yas_db_range_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_range_tests : XCTestCase

@end

@implementation yas_db_range_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create {
    db::range range{4, 2};

    XCTAssertEqual(range.location, 4);
    XCTAssertEqual(range.length, 2);
}

- (void)test_sql {
    db::range range{3, 5};

    XCTAssertEqual(range.sql(), "3, 5");
}

@end
