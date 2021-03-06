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
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertEqual(model.version().str(), "0.0.1");

    auto &entities = model.entities();
    XCTAssertEqual(entities.size(), 2);

    auto &entity_a = entities.at("sample_a");
    auto &attributes = entity_a.all_attributes;
    XCTAssertEqual(attributes.size(), 8);

    auto &id_attr = attributes.at(db::pk_id_field);
    XCTAssertEqual(id_attr.name, "pk_id");
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

    auto const &custom_attributes_a = entity_a.custom_attributes;
    XCTAssertEqual(custom_attributes_a.size(), 4);
    XCTAssertEqual(custom_attributes_a.count(db::pk_id_field), 0);
    XCTAssertEqual(custom_attributes_a.count(db::object_id_field), 0);
    XCTAssertEqual(custom_attributes_a.count(db::save_id_field), 0);
    XCTAssertEqual(custom_attributes_a.count(db::action_field), 0);
    XCTAssertEqual(custom_attributes_a.count("age"), 1);
    XCTAssertEqual(custom_attributes_a.count("name"), 1);
    XCTAssertEqual(custom_attributes_a.count("weight"), 1);
    XCTAssertEqual(custom_attributes_a.count("data"), 1);

    auto &entity_b = entities.at("sample_b");
    auto &attributes_b = entity_b.all_attributes;
    XCTAssertEqual(attributes_b.size(), 5);

    auto &id_attr_b = attributes_b.at(db::pk_id_field);
    XCTAssertEqual(id_attr_b.name, "pk_id");
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

    auto const &custom_attributes_b = entity_b.custom_attributes;
    XCTAssertEqual(custom_attributes_b.size(), 1);
    XCTAssertEqual(custom_attributes_b.count(db::pk_id_field), 0);
    XCTAssertEqual(custom_attributes_b.count(db::object_id_field), 0);
    XCTAssertEqual(custom_attributes_b.count(db::save_id_field), 0);
    XCTAssertEqual(custom_attributes_b.count(db::action_field), 0);
    XCTAssertEqual(custom_attributes_b.count("name"), 1);

    auto &relations = entity_a.relations;
    XCTAssertEqual(relations.size(), 1);

    auto &child = relations.at("child");
    XCTAssertEqual(child.source, "sample_a");
    XCTAssertEqual(child.name, "child");
    XCTAssertEqual(child.target, "sample_b");

    auto const &inv_rel_names_a = entity_a.inverse_relation_names;
    XCTAssertEqual(inv_rel_names_a.size(), 0);

    auto const &inv_rel_names_b = entity_b.inverse_relation_names;
    XCTAssertEqual(inv_rel_names_b.size(), 1);
    XCTAssertEqual(inv_rel_names_b.count("sample_a"), 1);
    auto const &sample_a_inv_rel_names = inv_rel_names_b.at("sample_a");
    XCTAssertEqual(sample_a_inv_rel_names.size(), 1);
    XCTAssertEqual(sample_a_inv_rel_names.count("child"), 1);
}

- (void)test_get_entity {
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertEqual(model.entity("sample_a").all_attributes.size(), 8);
    XCTAssertEqual(model.entity("sample_a").relations.size(), 1);
}

- (void)test_get_attributes_by_entity_name {
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertEqual(model.attributes("sample_a").size(), 8);
    XCTAssertEqual(model.attributes("sample_a").count("pk_id"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("obj_id"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("save_id"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("action"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("age"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("name"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("weight"), 1);
    XCTAssertEqual(model.attributes("sample_a").count("data"), 1);
}

- (void)test_get_attribute {
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertEqual(model.attribute("sample_a", "age").name, "age");
}

- (void)test_get_custom_attributes {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto const &attributes = model.custom_attributes("sample_a");
    XCTAssertEqual(attributes.size(), 4);
    XCTAssertEqual(attributes.count("name"), 1);
    XCTAssertEqual(attributes.count("age"), 1);
    XCTAssertEqual(attributes.count("weight"), 1);
    XCTAssertEqual(attributes.count("data"), 1);
}

- (void)test_get_relations_by_entity_name {
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertEqual(model.relations("sample_a").size(), 1);
    XCTAssertEqual(model.relations("sample_a").count("child"), 1);
}

- (void)test_get_relation {
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertEqual(model.relation("sample_a", "child").name, "child");
}

- (void)test_get_index {
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertEqual(model.index("sample_a_name").name, "sample_a_name");
}

- (void)test_entity_exists {
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertTrue(model.entity_exists("sample_a"));
    XCTAssertTrue(model.entity_exists("sample_b"));

    XCTAssertFalse(model.entity_exists("sample_c"));
}

- (void)test_attribute_exists {
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertTrue(model.attribute_exists("sample_a", "age"));
    XCTAssertTrue(model.attribute_exists("sample_b", "name"));

    XCTAssertFalse(model.attribute_exists("sample_a", "child"));
}

- (void)test_relation_exists {
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertTrue(model.relation_exists("sample_a", "child"));

    XCTAssertFalse(model.relation_exists("sample_a", "name"));
}

- (void)test_index_exists {
    db::model model = [yas_db_test_utils model_0_0_1];

    XCTAssertTrue(model.index_exists("sample_a_name"));
    XCTAssertFalse(model.index_exists("sample_b_name"));
}

@end
