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
    XCTAssertEqual(attributes.size(), 8);

    auto &id_attr = attributes.at(db::id_field);
    XCTAssertEqual(id_attr.name, "id");
    XCTAssertEqual(id_attr.type, "INTEGER");
    XCTAssertTrue(id_attr.default_value.type() == typeid(db::null));
    XCTAssertEqual(id_attr.not_null, false);
    XCTAssertEqual(id_attr.primary, true);
    XCTAssertEqual(id_attr.unique, false);

    auto &object_id_attr = attributes.at(db::object_id_field);
    XCTAssertEqual(object_id_attr.name, "obj_id");
    XCTAssertEqual(object_id_attr.type, "INTEGER");
    XCTAssertTrue(object_id_attr.default_value.type() == typeid(db::integer));
    XCTAssertEqual(object_id_attr.default_value.get<db::integer>(), 0);
    XCTAssertEqual(object_id_attr.not_null, true);
    XCTAssertEqual(object_id_attr.primary, false);
    XCTAssertEqual(object_id_attr.unique, false);

    auto &save_id_attr = attributes.at(db::save_id_field);
    XCTAssertEqual(save_id_attr.name, "save_id");
    XCTAssertEqual(save_id_attr.type, "INTEGER");
    XCTAssertTrue(save_id_attr.default_value.type() == typeid(db::integer));
    XCTAssertEqual(save_id_attr.default_value.get<db::integer>(), 0);
    XCTAssertEqual(save_id_attr.not_null, true);
    XCTAssertEqual(save_id_attr.primary, false);
    XCTAssertEqual(save_id_attr.unique, false);

    auto &action_attr = attributes.at(db::action_field);
    XCTAssertEqual(action_attr.name, "action");
    XCTAssertEqual(action_attr.type, "TEXT");
    XCTAssertTrue(action_attr.default_value.type() == typeid(db::text));
    XCTAssertEqual(action_attr.default_value.get<db::text>(), "insert");
    XCTAssertEqual(action_attr.not_null, true);
    XCTAssertEqual(action_attr.primary, false);
    XCTAssertEqual(action_attr.unique, false);

    auto &age = attributes.at("age");
    XCTAssertEqual(age.name, "age");
    XCTAssertEqual(age.type, "INTEGER");
    XCTAssertTrue(age.default_value.type() == typeid(db::integer));
    XCTAssertEqual(age.default_value.get<db::integer>(), 10);
    XCTAssertEqual(age.not_null, true);
    XCTAssertEqual(age.primary, false);
    XCTAssertEqual(age.unique, false);

    auto &name = attributes.at("name");
    XCTAssertEqual(name.name, "name");
    XCTAssertEqual(name.type, "TEXT");
    XCTAssertTrue(name.default_value.type() == typeid(db::text));
    XCTAssertEqual(name.default_value.get<db::text>(), "default_value");
    XCTAssertEqual(name.not_null, false);
    XCTAssertEqual(name.primary, false);
    XCTAssertEqual(name.unique, false);

    auto &weight = attributes.at("weight");
    XCTAssertEqual(weight.name, "weight");
    XCTAssertEqual(weight.type, "REAL");
    XCTAssertTrue(weight.default_value.type() == typeid(db::real));
    XCTAssertEqual(weight.default_value.get<db::real>(), 65.4);
    XCTAssertEqual(weight.not_null, false);
    XCTAssertEqual(weight.primary, false);
    XCTAssertEqual(weight.unique, false);

    auto &data = attributes.at("data");
    XCTAssertEqual(data.name, "data");
    XCTAssertEqual(data.type, "BLOB");
    XCTAssertTrue(data.default_value.type() == typeid(db::null));
    XCTAssertEqual(data.not_null, false);
    XCTAssertEqual(data.primary, false);
    XCTAssertEqual(data.unique, false);

    auto &entity_b = entities.at("sample_b");
    auto &attributes_b = entity_b.attributes;
    XCTAssertEqual(attributes_b.size(), 5);

    auto &id_attr_b = attributes_b.at(db::id_field);
    XCTAssertEqual(id_attr_b.name, "id");
    XCTAssertEqual(id_attr_b.type, "INTEGER");
    XCTAssertTrue(id_attr_b.default_value.type() == typeid(db::null));
    XCTAssertEqual(id_attr_b.not_null, false);
    XCTAssertEqual(id_attr_b.primary, true);
    XCTAssertEqual(id_attr_b.unique, false);

    auto &object_id_attr_b = attributes.at(db::object_id_field);
    XCTAssertEqual(object_id_attr_b.name, "obj_id");
    XCTAssertEqual(object_id_attr_b.type, "INTEGER");
    XCTAssertTrue(object_id_attr_b.default_value.type() == typeid(db::integer));
    XCTAssertEqual(object_id_attr_b.default_value.get<db::integer>(), 0);
    XCTAssertEqual(object_id_attr_b.not_null, true);
    XCTAssertEqual(object_id_attr_b.primary, false);
    XCTAssertEqual(object_id_attr_b.unique, false);

    auto &save_id_attr_b = attributes.at(db::save_id_field);
    XCTAssertEqual(save_id_attr_b.name, "save_id");
    XCTAssertEqual(save_id_attr_b.type, "INTEGER");
    XCTAssertTrue(save_id_attr_b.default_value.type() == typeid(db::integer));
    XCTAssertEqual(save_id_attr_b.default_value.get<db::integer>(), 0);
    XCTAssertEqual(save_id_attr_b.not_null, true);
    XCTAssertEqual(save_id_attr_b.primary, false);
    XCTAssertEqual(save_id_attr_b.unique, false);

    auto &action_attr_b = attributes.at(db::action_field);
    XCTAssertEqual(action_attr_b.name, "action");
    XCTAssertEqual(action_attr_b.type, "TEXT");
    XCTAssertTrue(action_attr_b.default_value.type() == typeid(db::text));
    XCTAssertEqual(action_attr_b.default_value.get<db::text>(), "insert");
    XCTAssertEqual(action_attr_b.not_null, true);
    XCTAssertEqual(action_attr_b.primary, false);
    XCTAssertEqual(action_attr_b.unique, false);

    auto &name_b = attributes_b.at("name");
    XCTAssertEqual(name_b.name, "name");
    XCTAssertEqual(name_b.type, "TEXT");
    XCTAssertTrue(name_b.default_value.type() == typeid(db::null));
    XCTAssertEqual(name_b.not_null, false);
    XCTAssertEqual(name_b.primary, false);
    XCTAssertEqual(name_b.unique, false);

    auto &relations = entity.relations;
    XCTAssertEqual(relations.size(), 1);

    auto &child = relations.at("child");
    XCTAssertEqual(child.entity_name, "sample_a");
    XCTAssertEqual(child.name, "child");
    XCTAssertEqual(child.target_entity_name, "sample_b");
}

- (void)test_get_entity {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    XCTAssertEqual(model.entity("sample_a").attributes.size(), 8);
    XCTAssertEqual(model.entity("sample_a").relations.size(), 1);
}

- (void)test_get_attributes_by_entity_name {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    XCTAssertEqual(model.attributes("sample_a").size(), 8);
    XCTAssertEqual(model.attributes("sample_a").count("id"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("obj_id"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("save_id"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("action"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("age"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("name"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("weight"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("data"), 1);
}

- (void)test_get_attribute {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    XCTAssertEqual(model.attribute("sample_a", "age").name, "age");
}

- (void)test_get_relations_by_entity_name {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    XCTAssertEqual(model.relations("sample_a").size(), 1);
    XCTAssertEqual(model.relations("sample_a").count("child"), 1);
}

- (void)test_get_relation {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    XCTAssertEqual(model.relation("sample_a", "child").name, "child");
}

- (void)test_entity_exists {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    XCTAssertTrue(model.entity_exists("sample_a"));
    XCTAssertTrue(model.entity_exists("sample_b"));

    XCTAssertFalse(model.entity_exists("sample_c"));
}

- (void)test_attribute_exists {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    XCTAssertTrue(model.attribute_exists("sample_a", "age"));
    XCTAssertTrue(model.attribute_exists("sample_b", "name"));

    XCTAssertFalse(model.attribute_exists("sample_a", "child"));
}

- (void)test_relation_exists {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    XCTAssertTrue(model.relation_exists("sample_a", "child"));

    XCTAssertFalse(model.relation_exists("sample_a", "name"));
}

@end
