//
//  yas_db_index_tests.mm
//

#import <XCTest/XCTest.h>
#import "yas_db_index.h"

using namespace yas;

@interface yas_db_index_tests : XCTestCase

@end

@implementation yas_db_index_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create {
    db::index index{"test_name", "test_table_name", std::vector<std::string>{"test_attr_name_0", "test_attr_name_1"}};

    XCTAssertEqual(index.name, "test_name");
    XCTAssertEqual(index.table_name, "test_table_name");
    XCTAssertEqual(index.attribute_names.size(), 2);
    XCTAssertEqual(index.attribute_names.at(0), "test_attr_name_0");
    XCTAssertEqual(index.attribute_names.at(1), "test_attr_name_1");
}

- (void)test_sql_for_create {
    db::index index{"idx_name", "tbl_name", std::vector<std::string>{"attr_0", "attr_1"}};

    XCTAssertEqual(index.sql_for_create(), "CREATE INDEX IF NOT EXISTS idx_name ON tbl_name(attr_0,attr_1);");
}

@end