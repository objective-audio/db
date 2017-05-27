//
//  yas_db_info_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_info_tests : XCTestCase

@end

@implementation yas_db_info_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_null_info {
    XCTAssertFalse(db::null_info());
}

@end
