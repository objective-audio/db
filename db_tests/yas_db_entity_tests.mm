//
//  yas_db_entity_tests.mm
//

#import "yas_db_test_utils.h"

#include <iostream>

using namespace yas;

@interface yas_db_entity_tests : XCTestCase

@end

@implementation yas_db_entity_tests

- (void)setUp {
    [super setUp];
    [yas_db_test_utils deleteDatabase];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_create {
    db::attribute_args attr{.name = "attr_name", .type = db::attribute_type::integer, .default_value = db::value{1}};
    db::relation_args rel{.name = "rel_name", .target = "test_target"};  //"entity_name"
    db::string_set_map_t inv_rels{{"inv_entity_name", {"inv_rel_name_1", "inv_rel_name_2"}}};

    db::entity entity{{.name = "entity_name", .attributes = {attr}, .relations = {rel}}, inv_rels};

    XCTAssertEqual(entity.name, "entity_name");
    XCTAssertEqual(entity.all_attributes.size(), 5);
    XCTAssertEqual(entity.custom_attributes.size(), 1);
    XCTAssertEqual(entity.relations.size(), 1);

    std::cout << entity.sql_for_create() << std::endl;
    std::cout << entity.sql_for_update() << std::endl;
}

@end
