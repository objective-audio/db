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

- (void)test_create_object {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model.entity("sample_a")};

    XCTAssertEqual(obj.entity().name, "sample_a");
    XCTAssertEqual(obj.entity_name(), "sample_a");
    XCTAssertFalse(obj.attribute_value("age"));
    XCTAssertFalse(obj.attribute_value("name"));
    XCTAssertFalse(obj.attribute_value("weight"));
    XCTAssertFalse(obj.object_id());
    XCTAssertEqual(obj.relation_ids("child").size(), 0);
    XCTAssertFalse(obj.is_removed());
}

- (void)test_load_values {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    db::value_map_t attributes{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                               std::make_pair("weight", db::value{53.4}), std::make_pair("hoge", db::value{"hage"})};
    db::value_vector_map_t relations{std::make_pair("child", db::value_vector_t{db::value{12}, db::value{34}})};
    db::object_data obj_data{.attributes = std::move(attributes), .relations = std::move(relations)};

    obj.manageable().load_data(obj_data);

    XCTAssertEqual(obj.attribute_value("age"), db::value{10});
    XCTAssertEqual(obj.attribute_value("name"), db::value{"name_val"});
    XCTAssertEqual(obj.attribute_value("weight"), db::value{53.4});
    XCTAssertThrows(obj.attribute_value("hoge"));

    XCTAssertEqual(obj.relation_size("child"), 2);
    XCTAssertEqual(obj.relation_id("child", 0), db::value{12});
    XCTAssertEqual(obj.relation_id("child", 1), db::value{34});
}

- (void)test_create_const_object {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::value_map_t attributes{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                               std::make_pair("weight", db::value{53.4}), std::make_pair("hoge", db::value{"hage"})};
    db::value_vector_map_t relations{std::make_pair("child", db::value_vector_t{db::value{12}, db::value{34}})};
    db::object_data obj_data{.attributes = std::move(attributes), .relations = std::move(relations)};

    db::const_object obj{model.entity("sample_a"), obj_data};

    XCTAssertEqual(obj.attribute_value("age"), db::value{10});
    XCTAssertEqual(obj.attribute_value("name"), db::value{"name_val"});
    XCTAssertEqual(obj.attribute_value("weight"), db::value{53.4});
    XCTAssertThrows(obj.attribute_value("hoge"));

    XCTAssertEqual(obj.relation_size("child"), 2);
    XCTAssertEqual(obj.relation_id("child", 0), db::value{12});
    XCTAssertEqual(obj.relation_id("child", 1), db::value{34});
}

- (void)test_reload_values {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    db::value_map_t prev_attributes{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                                    std::make_pair("weight", db::value{53.4}),
                                    std::make_pair("hoge", db::value{"hage"})};
    db::value_vector_map_t prev_relations{std::make_pair("child", db::value_vector_t{db::value{12}, db::value{34}})};
    db::object_data prev_obj_data{.attributes = std::move(prev_attributes), .relations = std::move(prev_relations)};

    obj.manageable().load_data(prev_obj_data);

    db::value_map_t post_attributes{std::make_pair("age", db::value{543}), std::make_pair("hoge", db::value{"poke"})};
    db::value_vector_map_t post_relations{
        std::make_pair("child", db::value_vector_t{db::value{234}, db::value{567}, db::value{890}})};
    db::object_data post_obj_data{.attributes = std::move(post_attributes), .relations = std::move(post_relations)};

    obj.manageable().load_data(post_obj_data);

    XCTAssertEqual(obj.attribute_value("age"), db::value{543});
    XCTAssertFalse(obj.attribute_value("name"));
    XCTAssertFalse(obj.attribute_value("weight"));
    XCTAssertThrows(obj.attribute_value("hoge"));

    XCTAssertEqual(obj.relation_size("child"), 3);
    XCTAssertEqual(obj.relation_id("child", 0), db::value{234});
    XCTAssertEqual(obj.relation_id("child", 1), db::value{567});
    XCTAssertEqual(obj.relation_id("child", 2), db::value{890});
}

- (void)test_set_and_get_value {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    obj.set_attribute_value("age", db::value{24});
    obj.set_attribute_value("name", db::value{"nabe"});
    obj.set_attribute_value("weight", db::value{5783.23});

    XCTAssertEqual(obj.attribute_value("age"), db::value{24});
    XCTAssertEqual(obj.attribute_value("name"), db::value{"nabe"});
    XCTAssertEqual(obj.attribute_value("weight"), db::value{5783.23});
}

- (void)test_add_and_remove_relation_id {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    obj.add_relation_id("child", db::value{321});

    XCTAssertEqual(obj.relation_ids("child").size(), 1);

    obj.add_relation_id("child", db::value{654});

    XCTAssertEqual(obj.relation_ids("child").size(), 2);

    obj.add_relation_id("child", db::value{987});

    XCTAssertEqual(obj.relation_ids("child").size(), 3);
    XCTAssertEqual(obj.relation_size("child"), 3);
    XCTAssertEqual(obj.relation_ids("child").at(0), db::value{321});
    XCTAssertEqual(obj.relation_ids("child").at(1), db::value{654});
    XCTAssertEqual(obj.relation_ids("child").at(2), db::value{987});
    XCTAssertEqual(obj.relation_id("child", 0), db::value{321});
    XCTAssertEqual(obj.relation_id("child", 1), db::value{654});
    XCTAssertEqual(obj.relation_id("child", 2), db::value{987});

    obj.remove_relation_id("child", db::value{654});

    XCTAssertEqual(obj.relation_size("child"), 2);
    XCTAssertEqual(obj.relation_id("child", 0), db::value{321});
    XCTAssertEqual(obj.relation_id("child", 1), db::value{987});

    obj.remove_relation_at("child", 0);

    XCTAssertEqual(obj.relation_size("child"), 1);
    XCTAssertEqual(obj.relation_id("child", 0), db::value{987});

    obj.remove_all_relations("child");

    XCTAssertEqual(obj.relation_size("child"), 0);
}

- (void)test_add_and_remove_relation_object {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model.entity("sample_a")};
    db::object obj_b1{nullptr, model.entity("sample_b")};
    db::object obj_b2{nullptr, model.entity("sample_b")};
    db::object obj_b3{nullptr, model.entity("sample_b")};
    obj_b1.set_attribute_value(db::object_id_field, db::value{5});
    obj_b2.set_attribute_value(db::object_id_field, db::value{6});
    obj_b3.set_attribute_value(db::object_id_field, db::value{7});

    obj.add_relation_object("child", obj_b1);

    XCTAssertEqual(obj.relation_ids("child").size(), 1);

    obj.add_relation_object("child", obj_b2);

    XCTAssertEqual(obj.relation_ids("child").size(), 2);

    obj.add_relation_object("child", obj_b3);

    XCTAssertEqual(obj.relation_ids("child").size(), 3);

    XCTAssertEqual(obj.relation_size("child"), 3);

    XCTAssertEqual(obj.relation_ids("child").at(0), db::value{5});
    XCTAssertEqual(obj.relation_ids("child").at(1), db::value{6});
    XCTAssertEqual(obj.relation_ids("child").at(2), db::value{7});
    XCTAssertEqual(obj.relation_id("child", 0), db::value{5});
    XCTAssertEqual(obj.relation_id("child", 1), db::value{6});
    XCTAssertEqual(obj.relation_id("child", 2), db::value{7});

    obj.remove_relation_object("child", obj_b2);

    XCTAssertEqual(obj.relation_size("child"), 2);
    XCTAssertEqual(obj.relation_id("child", 0), db::value{5});
    XCTAssertEqual(obj.relation_id("child", 1), db::value{7});

    obj.remove_relation_at("child", 0);

    XCTAssertEqual(obj.relation_size("child"), 1);
    XCTAssertEqual(obj.relation_id("child", 0), db::value{7});

    obj.remove_all_relations("child");

    XCTAssertEqual(obj.relation_size("child"), 0);
}

- (void)test_insert_relation_id {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model.entity("sample_a")};
    db::object obj_b1{nullptr, model.entity("sample_b")};
    db::object obj_b2{nullptr, model.entity("sample_b")};
    db::object obj_b3{nullptr, model.entity("sample_b")};
    obj_b1.set_attribute_value(db::object_id_field, db::value{5});
    obj_b2.set_attribute_value(db::object_id_field, db::value{6});
    obj_b3.set_attribute_value(db::object_id_field, db::value{7});

    obj.insert_relation_id("child", obj_b1.object_id(), 0);

    XCTAssertEqual(obj.relation_ids("child").size(), 1);

    obj.insert_relation_id("child", obj_b2.object_id(), 1);

    XCTAssertEqual(obj.relation_ids("child").size(), 2);

    obj.insert_relation_id("child", obj_b3.object_id(), 0);

    XCTAssertEqual(obj.relation_ids("child").size(), 3);

    XCTAssertEqual(obj.relation_id("child", 0), db::value{7});
    XCTAssertEqual(obj.relation_id("child", 1), db::value{5});
    XCTAssertEqual(obj.relation_id("child", 2), db::value{6});
}

- (void)test_insert_relation_object {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model.entity("sample_a")};
    db::object obj_b1{nullptr, model.entity("sample_b")};
    db::object obj_b2{nullptr, model.entity("sample_b")};
    db::object obj_b3{nullptr, model.entity("sample_b")};
    obj_b1.set_attribute_value(db::object_id_field, db::value{5});
    obj_b2.set_attribute_value(db::object_id_field, db::value{6});
    obj_b3.set_attribute_value(db::object_id_field, db::value{7});

    obj.insert_relation_object("child", obj_b1, 0);

    XCTAssertEqual(obj.relation_ids("child").size(), 1);

    obj.insert_relation_object("child", obj_b2, 1);

    XCTAssertEqual(obj.relation_ids("child").size(), 2);

    obj.insert_relation_object("child", obj_b3, 0);

    XCTAssertEqual(obj.relation_ids("child").size(), 3);

    XCTAssertEqual(obj.relation_id("child", 0), db::value{7});
    XCTAssertEqual(obj.relation_id("child", 1), db::value{5});
    XCTAssertEqual(obj.relation_id("child", 2), db::value{6});
}

- (void)test_replace_value {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    obj.set_attribute_value("age", db::value{1});

    XCTAssertEqual(obj.attribute_value("age"), db::value{1});

    obj.set_attribute_value("age", db::value{5});

    XCTAssertEqual(obj.attribute_value("age"), db::value{5});
}

- (void)test_remove {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    XCTAssertFalse(obj.is_removed());

    obj.set_attribute_value(db::pk_id_field, db::value{11});
    obj.set_attribute_value(db::object_id_field, db::value{45});
    obj.set_attribute_value("name", db::value{"tanaka"});
    obj.set_relation_ids("child", {db::value{111}});

    XCTAssertEqual(obj.attribute_value(db::object_id_field), db::value{45});
    XCTAssertEqual(obj.attribute_value("name"), db::value{"tanaka"});
    XCTAssertEqual(obj.relation_ids("child").at(0), db::value{111});

    obj.remove();

    XCTAssertTrue(obj.is_removed());
    XCTAssertFalse(obj.attribute_value("name"));
    XCTAssertEqual(obj.attribute_value(db::pk_id_field), db::value{11});
    XCTAssertEqual(obj.attribute_value(db::object_id_field), db::value{45});
    XCTAssertEqual(obj.relation_ids("child").size(), 0);
}

- (void)test_action {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};
    auto manageable_obj = obj.manageable();

    XCTAssertEqual(obj.action(), db::null_value());

    db::object_data obj_data{
        .attributes = db::value_map_t{std::make_pair(db::action_field, db::value{db::insert_action})},
        .relations = db::value_vector_map_t{std::make_pair("child", db::value_vector_t{db::value{12}, db::value{34}})}};
    obj.manageable().load_data(obj_data);
    XCTAssertEqual(obj.action(), db::value{db::insert_action});

    obj.set_attribute_value("name", db::value{"test_name"});
    XCTAssertEqual(obj.action(), db::value{db::update_action});

    manageable_obj.set_status(db::object_status::updating);
    obj.manageable().load_data(obj_data);
    XCTAssertEqual(obj.action(), db::value{db::insert_action});

    obj.add_relation_id("child", db::value{2});
    XCTAssertEqual(obj.action(), db::value{db::update_action});

    manageable_obj.set_status(db::object_status::updating);
    obj.manageable().load_data(obj_data);
    XCTAssertEqual(obj.action(), db::value{db::insert_action});

    obj.set_relation_ids("child", {db::value{1}});
    XCTAssertEqual(obj.action(), db::value{db::update_action});

    manageable_obj.set_status(db::object_status::updating);
    obj.manageable().load_data(obj_data);
    XCTAssertEqual(obj.action(), db::value{db::insert_action});

    obj.remove_relation_at("child", 0);
    XCTAssertEqual(obj.action(), db::value{db::update_action});

    manageable_obj.set_status(db::object_status::updating);
    obj.manageable().load_data(obj_data);
    XCTAssertEqual(obj.action(), db::value{db::insert_action});

    obj.remove_all_relations("child");
    XCTAssertEqual(obj.action(), db::value{db::update_action});

    manageable_obj.set_status(db::object_status::updating);
    obj.manageable().load_data(obj_data);
    XCTAssertEqual(obj.action(), db::value{db::insert_action});

    obj.remove();
    XCTAssertEqual(obj.action(), db::value{db::remove_action});
    XCTAssertTrue(obj.is_removed());
}

- (void)test_data_for_save {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    obj.set_attribute_value(db::pk_id_field, db::value{22});
    obj.set_attribute_value(db::object_id_field, db::value{55});
    obj.set_attribute_value("name", db::value{"suzuki"});
    obj.set_attribute_value("age", db::value{32});
    obj.set_attribute_value("weight", db::value{90.1});
    obj.set_attribute_value("data", db::null_value());
    obj.set_attribute_value(db::save_id_field, db::value{100});

    obj.set_relation_ids("child", db::value_vector_t{db::value{33}, db::value{44}});

    auto data = obj.data_for_save();

    XCTAssertGreaterThan(data.attributes.size(), 6);
    XCTAssertEqual(data.attributes.count(db::pk_id_field), 1);
    XCTAssertEqual(data.attributes.at(db::pk_id_field), db::value{22});
    XCTAssertEqual(data.attributes.count(db::object_id_field), 1);
    XCTAssertEqual(data.attributes.at(db::object_id_field), db::value{55});
    XCTAssertEqual(data.attributes.count(db::action_field), 1);
    XCTAssertEqual(data.attributes.at(db::action_field), db::value{db::update_action});
    XCTAssertEqual(data.attributes.count("name"), 1);
    XCTAssertEqual(data.attributes.at("name"), db::value{"suzuki"});
    XCTAssertEqual(data.attributes.count("age"), 1);
    XCTAssertEqual(data.attributes.at("age"), db::value{32});
    XCTAssertEqual(data.attributes.count("weight"), 1);
    XCTAssertEqual(data.attributes.at("weight"), db::value{90.1});
    XCTAssertEqual(data.attributes.count("data"), 1);
    XCTAssertEqual(data.attributes.at("data"), db::null_value());

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
    db::object obj{nullptr, model.entity("sample_a")};

    auto manageable_obj = obj.manageable();

    XCTAssertEqual(obj.status(), db::object_status::invalid);

    manageable_obj.set_status(db::object_status::inserted);

    XCTAssertEqual(obj.status(), db::object_status::inserted);

    manageable_obj.set_status(db::object_status::saved);

    XCTAssertEqual(obj.status(), db::object_status::saved);

    manageable_obj.set_status(db::object_status::changed);

    XCTAssertEqual(obj.status(), db::object_status::changed);

    manageable_obj.set_status(db::object_status::updating);

    XCTAssertEqual(obj.status(), db::object_status::updating);
}

- (void)test_relation_ids_for_fetch {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    obj.set_relation_ids("child", db::value_vector_t{db::value{1}, db::value{2}, db::value{3}, db::value{2}});

    XCTAssertEqual(obj.relation_size("child"), 4);

    auto rel_ids = obj.relation_ids_for_fetch();

    XCTAssertEqual(rel_ids.count("sample_b"), 1);

    auto const &sample_b_rel_ids = rel_ids.at("sample_b");

    XCTAssertEqual(sample_b_rel_ids.size(), 3);
    XCTAssertEqual(sample_b_rel_ids.count(1), 1);
    XCTAssertEqual(sample_b_rel_ids.count(2), 1);
    XCTAssertEqual(sample_b_rel_ids.count(3), 1);
    XCTAssertEqual(sample_b_rel_ids.count(4), 0);
}

- (void)test_relation_ids_from_many_objects {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj1{nullptr, model.entity("sample_a")};
    obj1.set_relation_ids("child", db::value_vector_t{db::value{1}, db::value{2}, db::value{3}});

    db::object obj2{nullptr, model.entity("sample_a")};
    obj2.set_relation_ids("child", db::value_vector_t{db::value{5}, db::value{4}, db::value{3}});

    auto rel_ids =
        db::relation_ids(db::object_vector_map_t{std::make_pair("sample_a", db::object_vector_t{obj1, obj2})});

    XCTAssertEqual(rel_ids.count("sample_b"), 1);

    auto const &sample_b_ids = rel_ids.at("sample_b");

    XCTAssertEqual(sample_b_ids.size(), 5);
}

- (void)test_observe_attribute {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model.entity("sample_a")};

    bool called = false;

    auto observer = obj.subject().make_wild_card_observer([&called, self](auto const &context) {
        auto const &key = context.key;
        auto const &info = context.value;

        XCTAssertEqual(key, db::object::method::attribute_changed);

        auto const &obj = info.object;
        auto const &name = info.name;

        XCTAssertEqual(name, "name");
        XCTAssertEqual(obj.attribute_value(name), db::value{"test_value"});

        called = true;
    });

    obj.set_attribute_value("name", db::value{"test_value"});

    XCTAssertTrue(called);
}

- (void)test_observe_relation {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model.entity("sample_a")};

    size_t called_count = 0;

    auto observer = obj.subject().make_wild_card_observer([&called_count, self](auto const &context) {
        auto const &key = context.key;
        auto const &info = context.value;

        XCTAssertEqual(key, db::object::method::relation_changed);

        auto const &obj = info.object;
        auto const &name = info.name;
        auto const &rel_info = info.relation_change_info();

        XCTAssertEqual(name, "child");

        if (called_count == 0) {
            XCTAssertEqual(obj.relation_size(name), 2);
            XCTAssertEqual(obj.relation_id(name, 0), db::value{10});
            XCTAssertEqual(obj.relation_id(name, 1), db::value{20});
            XCTAssertEqual(rel_info.reason, db::object::change_reason::replaced);
            XCTAssertEqual(rel_info.indices.size(), 0);
        } else if (called_count == 1) {
            XCTAssertEqual(obj.relation_size(name), 3);
            XCTAssertEqual(obj.relation_id(name, 2), db::value{30});
            XCTAssertEqual(rel_info.reason, db::object::change_reason::inserted);
            XCTAssertEqual(rel_info.indices.size(), 1);
        } else if (called_count == 2) {
            XCTAssertEqual(obj.relation_size(name), 2);
            XCTAssertEqual(obj.relation_id(name, 0), db::value{10});
            XCTAssertEqual(obj.relation_id(name, 1), db::value{30});
            XCTAssertEqual(rel_info.reason, db::object::change_reason::removed);
            XCTAssertEqual(rel_info.indices.size(), 1);
        } else if (called_count == 3) {
            XCTAssertEqual(obj.relation_size(name), 0);
            XCTAssertEqual(rel_info.reason, db::object::change_reason::removed);
            XCTAssertEqual(rel_info.indices.size(), 2);
        }

        ++called_count;
    });

    obj.set_relation_ids("child", db::value_vector_t{db::value{10}, db::value{20}});

    XCTAssertEqual(called_count, 1);

    obj.add_relation_id("child", db::value{30});

    XCTAssertEqual(called_count, 2);

    obj.remove_relation_id("child", db::value{20});

    XCTAssertEqual(called_count, 3);

    obj.remove_all_relations("child");

    XCTAssertEqual(called_count, 4);
}

- (void)test_observe_loading {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model.entity("sample_a")};

    bool called = false;

    auto observer = obj.subject().make_wild_card_observer([&called, self](auto const &context) {
        auto const &key = context.key;
        auto const &info = context.value;

        XCTAssertEqual(key, db::object::method::loading_changed);

        auto const &obj = info.object;
        auto const &name = info.name;

        XCTAssertEqual(name.size(), 0);

        XCTAssertEqual(obj.attribute_value("age"), db::value{10});
        XCTAssertEqual(obj.attribute_value("name"), db::value{"name_val"});
        XCTAssertEqual(obj.attribute_value("weight"), db::value{53.4});

        XCTAssertEqual(obj.relation_size("child"), 2);
        XCTAssertEqual(obj.relation_id("child", 0), db::value{55});
        XCTAssertEqual(obj.relation_id("child", 1), db::value{66});

        called = true;
    });

    db::value_map_t attributes{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                               std::make_pair("weight", db::value{53.4})};
    db::value_vector_map_t relations{std::make_pair("child", db::value_vector_t{db::value{55}, db::value{66}})};
    db::object_data obj_data{.attributes = std::move(attributes), .relations = std::move(relations)};

    obj.manageable().load_data(obj_data);

    XCTAssertTrue(called);
}

- (void)test_clear {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model.entity("sample_a")};

    obj.set_attribute_value("age", db::value{20});
    obj.set_attribute_value("name", db::value{"test_name"});
    obj.set_relation_ids("child", {db::value{23}, db::value{45}});

    XCTAssertEqual(obj.status(), db::object_status::changed);

    XCTAssertEqual(obj.attribute_value("age"), db::value{20});
    XCTAssertEqual(obj.attribute_value("name"), db::value{"test_name"});
    XCTAssertEqual(obj.relation_id("child", 0), db::value{23});
    XCTAssertEqual(obj.relation_id("child", 1), db::value{45});

    obj.manageable().clear_data();

    XCTAssertEqual(obj.status(), db::object_status::invalid);

    XCTAssertFalse(obj.attribute_value("age"));
    XCTAssertFalse(obj.attribute_value("name"));
    XCTAssertEqual(obj.relation_size("child"), 0);
}

- (void)test_observe_clear {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model.entity("sample_a")};

    obj.set_attribute_value("name", db::value{"test_name"});
    obj.set_relation_ids("child", {db::value{101}, db::value{102}});

    XCTAssertEqual(obj.status(), db::object_status::changed);

    bool called = false;

    auto observer = obj.subject().make_wild_card_observer([&called, self](auto const &context) {
        auto const &key = context.key;
        auto const &info = context.value;

        XCTAssertEqual(key, db::object::method::loading_changed);

        auto const &obj = info.object;
        auto const &name = info.name;

        XCTAssertEqual(obj.status(), db::object_status::invalid);

        XCTAssertEqual(name.size(), 0);

        XCTAssertFalse(obj.attribute_value("name"));
        XCTAssertEqual(obj.relation_size("child"), 0);

        called = true;
    });

    obj.manageable().clear_data();

    XCTAssertTrue(called);
}

- (void)test_move {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{nullptr, model.entity("sample_a")};

    XCTAssertTrue(obj);

    db::object obj2 = std::move(obj);

    XCTAssertTrue(obj2);
    XCTAssertFalse(obj);

    auto obj3 = db::null_object();

    obj3 = std::move(obj2);

    XCTAssertTrue(obj3);
    XCTAssertFalse(obj2);
}

- (void)test_const_move {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::value_map_t attributes{std::make_pair("age", db::value{10})};
    db::object_data obj_data{.attributes = std::move(attributes)};

    db::const_object obj{model.entity("sample_a"), obj_data};

    db::const_object obj2 = std::move(obj);

    XCTAssertTrue(obj2);
    XCTAssertFalse(obj);

    auto obj3 = db::null_const_object();

    obj3 = std::move(obj2);

    XCTAssertTrue(obj3);
    XCTAssertFalse(obj2);
}

- (void)test_object_status_to_string {
    XCTAssertEqual(to_string(db::object_status::invalid), "invalid");
    XCTAssertEqual(to_string(db::object_status::inserted), "inserted");
    XCTAssertEqual(to_string(db::object_status::saved), "saved");
    XCTAssertEqual(to_string(db::object_status::changed), "changed");
    XCTAssertEqual(to_string(db::object_status::updating), "updating");
}

- (void)test_is_inserted {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    obj.set_attribute_value(db::action_field, db::value{db::insert_action});

    XCTAssertTrue(obj.is_inserted());

    obj.set_attribute_value(db::action_field, db::value{db::update_action});

    XCTAssertFalse(obj.is_inserted());

    obj.set_attribute_value(db::action_field, db::value{db::remove_action});

    XCTAssertFalse(obj.is_inserted());
}

- (void)test_is_updated {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    obj.set_attribute_value(db::action_field, db::value{db::update_action});

    XCTAssertTrue(obj.is_updated());

    obj.set_attribute_value(db::action_field, db::value{db::insert_action});

    XCTAssertFalse(obj.is_updated());

    obj.set_attribute_value(db::action_field, db::value{db::remove_action});

    XCTAssertFalse(obj.is_updated());
}

- (void)test_is_removed {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{nullptr, model.entity("sample_a")};

    obj.set_attribute_value(db::action_field, db::value{db::remove_action});

    XCTAssertTrue(obj.is_removed());

    obj.set_attribute_value(db::action_field, db::value{db::insert_action});

    XCTAssertFalse(obj.is_removed());

    obj.set_attribute_value(db::action_field, db::value{db::update_action});

    XCTAssertFalse(obj.is_removed());
}

@end
