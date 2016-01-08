//
//  yas_db_model_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_model_tests : XCTestCase

@end

@implementation yas_db_model_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_load_model {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];

    db::model model((__bridge CFDictionaryRef)model_dict);

    XCTAssertEqual(model.version().str(), "0.0.1");

    auto &entities = model.entities();
    XCTAssertEqual(entities.size(), 2);

    auto &entity = entities.at("sample_a");
    auto &attributes = entity.attributes;
    XCTAssertEqual(attributes.size(), 5);

    auto &id_attr = attributes.at(db::id_field);
    XCTAssertEqual(id_attr.name, "id");
    XCTAssertEqual(id_attr.type, "integer");
    XCTAssertTrue(id_attr.default_value.type() == typeid(db::null));
    XCTAssertEqual(id_attr.not_null, false);
    XCTAssertEqual(id_attr.primary, true);

    auto &age = attributes.at("age");
    XCTAssertEqual(age.name, "age");
    XCTAssertEqual(age.type, "integer");
    XCTAssertTrue(age.default_value.type() == typeid(db::integer));
    XCTAssertEqual(age.default_value.get<db::integer>(), 10);
    XCTAssertEqual(age.not_null, true);
    XCTAssertEqual(age.primary, false);

    auto &name = attributes.at("name");
    XCTAssertEqual(name.name, "name");
    XCTAssertEqual(name.type, "text");
    XCTAssertTrue(name.default_value.type() == typeid(db::text));
    XCTAssertEqual(name.default_value.get<db::text>(), "default_value");
    XCTAssertEqual(name.not_null, false);
    XCTAssertEqual(name.primary, false);

    auto &weight = attributes.at("weight");
    XCTAssertEqual(weight.name, "weight");
    XCTAssertEqual(weight.type, "real");
    XCTAssertTrue(weight.default_value.type() == typeid(db::real));
    XCTAssertEqual(weight.default_value.get<db::real>(), 65.4);
    XCTAssertEqual(weight.not_null, false);
    XCTAssertEqual(weight.primary, false);

    auto &data = attributes.at("data");
    XCTAssertEqual(data.name, "data");
    XCTAssertEqual(data.type, "blob");
    XCTAssertTrue(data.default_value.type() == typeid(db::null));
    XCTAssertEqual(data.not_null, false);
    XCTAssertEqual(data.primary, false);

    auto &entity_b = entities.at("sample_b");
    auto &attributes_b = entity_b.attributes;
    XCTAssertEqual(attributes_b.size(), 2);

    auto &id_attr_b = attributes_b.at(db::id_field);
    XCTAssertEqual(id_attr_b.name, "id");
    XCTAssertEqual(id_attr_b.type, "integer");
    XCTAssertTrue(id_attr_b.default_value.type() == typeid(db::null));
    XCTAssertEqual(id_attr_b.not_null, false);
    XCTAssertEqual(id_attr_b.primary, true);

    auto &name_b = attributes_b.at("name");
    XCTAssertEqual(name_b.name, "name");
    XCTAssertEqual(name_b.type, "text");
    XCTAssertTrue(name_b.default_value.type() == typeid(db::null));
    XCTAssertEqual(name_b.not_null, false);
    XCTAssertEqual(name_b.primary, false);

    auto &relations = entity.relations;
    XCTAssertEqual(relations.size(), 1);

    auto &child = relations.at("child");
    XCTAssertEqual(child.entity_name, "sample_a");
    XCTAssertEqual(child.name, "child");
    XCTAssertEqual(child.target_entity_name, "sample_b");
}

@end
