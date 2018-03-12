//
//  yas_db_entity_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_entity_tests : XCTestCase

@end

@implementation yas_db_entity_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_create {
    db::attribute attr{{.name = "attr_name", .type = db::attribute_type::integer, .default_value = db::value{1}}};
    db::relation rel{{.name = "rel_name", .target = "test_target"}, "entity_name"};
    db::string_set_map_t inv_rels{{"inv_entity_name", {"inv_rel_name_1", "inv_rel_name_2"}}};

    db::entity entity{"entity_name", {{attr.name, std::move(attr)}}, {{rel.name, std::move(rel)}}, std::move(inv_rels)};

    XCTAssertEqual(entity.name, "entity_name");
    XCTAssertEqual(entity.all_attributes.size(), 1);
    XCTAssertEqual(entity.custom_attributes.size(), 1);
    XCTAssertEqual(entity.relations.size(), 1);

    XCTAssertEqual(entity.sql_for_create(), "CREATE TABLE IF NOT EXISTS entity_name (attr_name INTEGER DEFAULT 1);");
    XCTAssertEqual(entity.sql_for_update(), "UPDATE entity_name SET attr_name = :attr_name WHERE (pk_id = :pk_id);");
}

@end
