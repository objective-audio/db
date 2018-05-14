//
//  yas_db_index_tests.mm
//

#import <XCTest/XCTest.h>
#import "yas_db_additional_types.h"
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
    db::index index{{.name = "test_name",
                     .entity = "test_table_name",
                     .attributes = std::vector<std::string>{"test_attr_name_0", "test_attr_name_1"}}};

    XCTAssertEqual(index.name, "test_name");
    XCTAssertEqual(index.entity, "test_table_name");
    XCTAssertEqual(index.attributes.size(), 2);
    XCTAssertEqual(index.attributes.at(0), "test_attr_name_0");
    XCTAssertEqual(index.attributes.at(1), "test_attr_name_1");
}

- (void)test_sql_for_create {
    db::index index{
        {.name = "idx_name", .entity = "tbl_name", .attributes = std::vector<std::string>{"attr_0", "attr_1"}}};

    XCTAssertEqual(index.sql_for_create(), "CREATE INDEX IF NOT EXISTS idx_name ON tbl_name(attr_0,attr_1);");
}

@end
