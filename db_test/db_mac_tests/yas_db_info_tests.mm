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

- (void)test_create {
    db::info info{"1.0.0", 1, 2};

    XCTAssertEqual(info.version(), yas::version{"1.0.0"});
    XCTAssertEqual(info.current_save_id(), 1);
    XCTAssertEqual(info.last_save_id(), 2);
    XCTAssertEqual(info.current_save_id_value(), db::value{1});
    XCTAssertEqual(info.last_save_id_value(), db::value{2});
}

- (void)test_create_with_values {
    db::value_map_t values{{db::version_field, db::value{"1.2.3"}},
                           {db::current_save_id_field, db::value{10}},
                           {db::last_save_id_field, db::value{20}}};
}

@end
