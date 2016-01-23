//
//  yas_db_object_tests.mm
//

#import <XCTest/XCTest.h>
#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_object_tests : XCTestCase

@end

@implementation yas_db_object_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model, "sample_a"};

    XCTAssertEqual(obj.model(), model);
    XCTAssertEqual(obj.entity_name(), "sample_a");
    XCTAssertEqual(obj.get_attribute("age"), nullptr);
    XCTAssertEqual(obj.get_attribute("name"), nullptr);
    XCTAssertEqual(obj.get_attribute("weight"), nullptr);
    XCTAssertEqual(obj.object_id(), nullptr);
    XCTAssertEqual(obj.get_relation("child").size(), 0);
    XCTAssertFalse(obj.is_removed());
}

- (void)test_load_values {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model, "sample_a"};

    db::value_map attributes{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                             std::make_pair("weight", db::value{53.4}), std::make_pair("hoge", db::value{"hage"})};
    db::value_vector_map relations{std::make_pair("child", db::value_vector{db::value{12}, db::value{34}})};
    db::object_data obj_data{.attributes = std::move(attributes), .relations = std::move(relations)};

    obj.load_data(obj_data);

    XCTAssertEqual(obj.get_attribute("age"), db::value{10});
    XCTAssertEqual(obj.get_attribute("name"), db::value{"name_val"});
    XCTAssertEqual(obj.get_attribute("weight"), db::value{53.4});
    XCTAssertEqual(obj.get_attribute("hoge"), nullptr);

    XCTAssertEqual(obj.relation_size("child"), 2);
    XCTAssertEqual(obj.get_relation("child", 0), db::value{12});
    XCTAssertEqual(obj.get_relation("child", 1), db::value{34});
}

- (void)test_reload_values {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model, "sample_a"};

    db::value_map prev_attributes{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                                  std::make_pair("weight", db::value{53.4}), std::make_pair("hoge", db::value{"hage"})};
    db::value_vector_map prev_relations{std::make_pair("child", db::value_vector{db::value{12}, db::value{34}})};
    db::object_data prev_obj_data{.attributes = std::move(prev_attributes), .relations = std::move(prev_relations)};

    obj.load_data(prev_obj_data);

    db::value_map post_attributes{std::make_pair("age", db::value{543}), std::make_pair("hoge", db::value{"poke"})};
    db::value_vector_map post_relations{
        std::make_pair("child", db::value_vector{db::value{234}, db::value{567}, db::value{890}})};
    db::object_data post_obj_data{.attributes = std::move(post_attributes), .relations = std::move(post_relations)};

    obj.load_data(post_obj_data);

    XCTAssertEqual(obj.get_attribute("age"), db::value{543});
    XCTAssertEqual(obj.get_attribute("name"), nullptr);
    XCTAssertEqual(obj.get_attribute("weight"), nullptr);
    XCTAssertEqual(obj.get_attribute("hoge"), nullptr);

    XCTAssertEqual(obj.relation_size("child"), 3);
    XCTAssertEqual(obj.get_relation("child", 0), db::value{234});
    XCTAssertEqual(obj.get_relation("child", 1), db::value{567});
    XCTAssertEqual(obj.get_relation("child", 2), db::value{890});
}

- (void)test_set_and_get_value {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model, "sample_a"};

    obj.set_value("age", db::value{24});
    obj.set_value("name", db::value{"nabe"});
    obj.set_value("weight", db::value{5783.23});

    XCTAssertEqual(obj.get_attribute("age"), db::value{24});
    XCTAssertEqual(obj.get_attribute("name"), db::value{"nabe"});
    XCTAssertEqual(obj.get_attribute("weight"), db::value{5783.23});
}

- (void)test_push_back_and_erase_relation {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model, "sample_a"};

    obj.push_back_relation("child", db::value{321});

    XCTAssertEqual(obj.get_relation("child").size(), 1);

    obj.push_back_relation("child", db::value{654});

    XCTAssertEqual(obj.get_relation("child").size(), 2);

    obj.push_back_relation("child", db::value{987});

    XCTAssertEqual(obj.get_relation("child").size(), 3);
    XCTAssertEqual(obj.relation_size("child"), 3);
    XCTAssertEqual(obj.get_relation("child").at(0), db::value{321});
    XCTAssertEqual(obj.get_relation("child").at(1), db::value{654});
    XCTAssertEqual(obj.get_relation("child").at(2), db::value{987});
    XCTAssertEqual(obj.get_relation("child", 0), db::value{321});
    XCTAssertEqual(obj.get_relation("child", 1), db::value{654});
    XCTAssertEqual(obj.get_relation("child", 2), db::value{987});

    obj.erase_relation("child", db::value{654});

    XCTAssertEqual(obj.relation_size("child"), 2);
    XCTAssertEqual(obj.get_relation("child", 0), db::value{321});
    XCTAssertEqual(obj.get_relation("child", 1), db::value{987});

    obj.erase_relation("child", 0);

    XCTAssertEqual(obj.relation_size("child"), 1);
    XCTAssertEqual(obj.get_relation("child", 0), db::value{987});

    obj.clear_relation("child");

    XCTAssertEqual(obj.relation_size("child"), 0);
}

- (void)test_replace_value {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model, "sample_a"};

    obj.set_value("age", db::value{1});

    XCTAssertEqual(obj.get_attribute("age"), db::value{1});

    obj.set_value("age", db::value{5});

    XCTAssertEqual(obj.get_attribute("age"), db::value{5});
}

- (void)test_remove {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model, "sample_a"};

    XCTAssertFalse(obj.is_removed());

    obj.set_value(db::id_field, db::value{11});
    obj.set_value(db::object_id_field, db::value{45});
    obj.set_value("name", db::value{"tanaka"});
    obj.set_relation("child", {db::value{111}});

    XCTAssertEqual(obj.get_attribute(db::object_id_field), db::value{45});
    XCTAssertEqual(obj.get_attribute("name"), db::value{"tanaka"});
    XCTAssertEqual(obj.get_relation("child").at(0), db::value{111});

    obj.remove();

    XCTAssertTrue(obj.is_removed());
    XCTAssertEqual(obj.get_attribute("name"), nullptr);
    XCTAssertEqual(obj.get_attribute(db::id_field), db::value{11});
    XCTAssertEqual(obj.get_attribute(db::object_id_field), db::value{45});
    XCTAssertEqual(obj.get_relation("child").size(), 0);
}

- (void)test_data_for_save {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model, "sample_a"};

    obj.set_value(db::id_field, db::value{22});
    obj.set_value(db::object_id_field, db::value{55});
    obj.set_value("name", db::value{"suzuki"});
    obj.set_value("age", db::value{32});
    obj.set_value("weight", db::value{90.1});
    obj.set_value("data", db::value::empty());
    obj.set_value(db::save_id_field, db::value{100});

    obj.set_relation("child", db::value_vector{db::value{33}, db::value{44}});

    auto data = obj.data_for_save();

    XCTAssertGreaterThan(data.attributes.size(), 6);
    XCTAssertEqual(data.attributes.count(db::id_field), 1);
    XCTAssertEqual(data.attributes.at(db::id_field), db::value{22});
    XCTAssertEqual(data.attributes.count(db::object_id_field), 1);
    XCTAssertEqual(data.attributes.at(db::object_id_field), db::value{55});
    XCTAssertEqual(data.attributes.count("name"), 1);
    XCTAssertEqual(data.attributes.at("name"), db::value{"suzuki"});
    XCTAssertEqual(data.attributes.count("age"), 1);
    XCTAssertEqual(data.attributes.at("age"), db::value{32});
    XCTAssertEqual(data.attributes.count("weight"), 1);
    XCTAssertEqual(data.attributes.at("weight"), db::value{90.1});
    XCTAssertEqual(data.attributes.count("data"), 1);
    XCTAssertEqual(data.attributes.at("data"), db::value::empty());

    XCTAssertEqual(data.relations.size(), 1);
    XCTAssertEqual(data.relations.count("child"), 1);
    XCTAssertEqual(data.relations.at("child").size(), 2);
    XCTAssertEqual(data.relations.at("child").at(0), db::value{33});
    XCTAssertEqual(data.relations.at("child").at(1), db::value{44});

    XCTAssertEqual(data.attributes.count(db::save_id_field), 0);
}

- (void)test_change_status {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model, "sample_a"};

    auto *manageable_obj = dynamic_cast<db::manageable *>(&obj);

    XCTAssertEqual(obj.status(), db::object_status::invalid);

    manageable_obj->set_status(db::object_status::saved);

    XCTAssertEqual(obj.status(), db::object_status::saved);

    manageable_obj->set_status(db::object_status::changed);

    XCTAssertEqual(obj.status(), db::object_status::changed);

    manageable_obj->set_status(db::object_status::updating);

    XCTAssertEqual(obj.status(), db::object_status::updating);
}

@end
