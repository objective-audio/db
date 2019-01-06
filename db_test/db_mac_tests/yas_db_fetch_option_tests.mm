//
//  yas_db_fetch_option_tests.mm
//

#import <XCTest/XCTest.h>
#import <db/yas_db_fetch_option.h>

using namespace yas;

@interface yas_db_fetch_option_tests : XCTestCase

@end

@implementation yas_db_fetch_option_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_construct {
    db::fetch_option option;
    XCTAssertEqual(option.select_options().size(), 0);
}

- (void)test_construct_with_reserve {
    db::fetch_option option{3};
    XCTAssertEqual(option.select_options().size(), 0);
}

- (void)test_add_select_option {
    db::fetch_option option;

    option.add_select_option({.table = "table_a"});

    XCTAssertEqual(option.select_options().size(), 1);

    option.add_select_option({.table = "table_b"});

    XCTAssertEqual(option.select_options().size(), 2);
    XCTAssertEqual(option.select_options().at("table_a").table, "table_a");
    XCTAssertEqual(option.select_options().at("table_b").table, "table_b");
}

@end
