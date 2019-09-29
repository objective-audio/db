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
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));

    XCTAssertEqual(obj->entity().name, "sample_a");
    XCTAssertEqual(obj->entity_name(), "sample_a");
    XCTAssertFalse(obj->attribute_value("age"));
    XCTAssertFalse(obj->attribute_value("name"));
    XCTAssertFalse(obj->attribute_value("weight"));
    XCTAssertTrue(obj->object_id().is_temporary());
    XCTAssertEqual(obj->relation_ids("child").size(), 0);
    XCTAssertFalse(obj->is_removed());
}

- (void)test_load_values {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    db::object_id obj_id = db::make_stable_id(db::value{1});
    db::value_map_t attributes{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                               std::make_pair("weight", db::value{53.4}), std::make_pair("hoge", db::value{"hage"})};
    db::id_vector_map_t relations{
        std::make_pair("child", db::id_vector_t{db::make_stable_id(12), db::make_stable_id(34)})};
    db::object_data obj_data{
        .object_id = std::move(obj_id), .attributes = std::move(attributes), .relations = std::move(relations)};

    obj->manageable().load_data(obj_data);

    XCTAssertEqual(obj->object_id().stable_value(), db::value{1});

    XCTAssertEqual(obj->attribute_value("age"), db::value{10});
    XCTAssertEqual(obj->attribute_value("name"), db::value{"name_val"});
    XCTAssertEqual(obj->attribute_value("weight"), db::value{53.4});
    XCTAssertThrows(obj->attribute_value("hoge"));

    XCTAssertEqual(obj->relation_size("child"), 2);
    XCTAssertEqual(obj->relation_id("child", 0).stable(), 12);
    XCTAssertEqual(obj->relation_id("child", 1).stable(), 34);
}

- (void)test_create_const_object {
    db::model model = [yas_db_test_utils model_0_0_1];

    db::object_id obj_id = db::make_stable_id(db::value{1});
    db::value_map_t attributes{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                               std::make_pair("weight", db::value{53.4}), std::make_pair("hoge", db::value{"hage"})};
    db::id_vector_map_t relations{
        std::make_pair("child", db::id_vector_t{db::make_stable_id(12), db::make_stable_id(34)})};
    db::object_data obj_data{
        .object_id = std::move(obj_id), .attributes = std::move(attributes), .relations = std::move(relations)};

    auto obj = db::const_object::make_shared(model.entity("sample_a"), obj_data);

    XCTAssertEqual(obj->object_id().stable_value(), db::value{1});

    XCTAssertEqual(obj->attribute_value("age"), db::value{10});
    XCTAssertEqual(obj->attribute_value("name"), db::value{"name_val"});
    XCTAssertEqual(obj->attribute_value("weight"), db::value{53.4});
    XCTAssertThrows(obj->attribute_value("hoge"));

    XCTAssertEqual(obj->relation_size("child"), 2);
    XCTAssertEqual(obj->relation_id("child", 0).stable(), 12);
    XCTAssertEqual(obj->relation_id("child", 1).stable(), 34);
}

- (void)test_reload_values {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    db::object_id obj_id = db::make_stable_id(db::value{1});
    db::value_map_t prev_attributes{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                                    std::make_pair("weight", db::value{53.4}),
                                    std::make_pair("hoge", db::value{"hage"})};
    db::id_vector_map_t prev_relations{
        std::make_pair("child", db::id_vector_t{db::make_stable_id(12), db::make_stable_id(34)})};
    db::object_data prev_obj_data{.object_id = std::move(obj_id),
                                  .attributes = std::move(prev_attributes),
                                  .relations = std::move(prev_relations)};

    obj->manageable().load_data(prev_obj_data);

    db::object_id post_obj_id = db::make_stable_id(db::value{1});
    db::value_map_t post_attributes{std::make_pair("age", db::value{543}), std::make_pair("hoge", db::value{"poke"})};
    db::id_vector_map_t post_relations{std::make_pair(
        "child", db::id_vector_t{db::make_stable_id(234), db::make_stable_id(567), db::make_stable_id(890)})};
    db::object_data post_obj_data{.object_id = std::move(post_obj_id),
                                  .attributes = std::move(post_attributes),
                                  .relations = std::move(post_relations)};

    obj->manageable().load_data(post_obj_data);

    XCTAssertEqual(obj->object_id().stable_value(), db::value{1});

    XCTAssertEqual(obj->attribute_value("age"), db::value{543});
    XCTAssertFalse(obj->attribute_value("name"));
    XCTAssertFalse(obj->attribute_value("weight"));
    XCTAssertThrows(obj->attribute_value("hoge"));

    XCTAssertEqual(obj->relation_size("child"), 3);
    XCTAssertEqual(obj->relation_id("child", 0).stable(), 234);
    XCTAssertEqual(obj->relation_id("child", 1).stable(), 567);
    XCTAssertEqual(obj->relation_id("child", 2).stable(), 890);
}

- (void)test_set_and_get_value {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    obj->set_attribute_value("age", db::value{24});
    obj->set_attribute_value("name", db::value{"nabe"});
    obj->set_attribute_value("weight", db::value{5783.23});

    XCTAssertEqual(obj->attribute_value("age"), db::value{24});
    XCTAssertEqual(obj->attribute_value("name"), db::value{"nabe"});
    XCTAssertEqual(obj->attribute_value("weight"), db::value{5783.23});
}

- (void)test_add_and_remove_relation_id {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    obj->add_relation_id("child", db::make_stable_id(db::value{321}));

    XCTAssertEqual(obj->relation_ids("child").size(), 1);

    obj->add_relation_id("child", db::make_stable_id(db::value{654}));

    XCTAssertEqual(obj->relation_ids("child").size(), 2);

    obj->add_relation_id("child", db::make_stable_id(db::value{987}));

    XCTAssertEqual(obj->relation_ids("child").size(), 3);
    XCTAssertEqual(obj->relation_size("child"), 3);
    XCTAssertEqual(obj->relation_ids("child").at(0).stable(), 321);
    XCTAssertEqual(obj->relation_ids("child").at(1).stable(), 654);
    XCTAssertEqual(obj->relation_ids("child").at(2).stable(), 987);
    XCTAssertEqual(obj->relation_id("child", 0).stable(), 321);
    XCTAssertEqual(obj->relation_id("child", 1).stable(), 654);
    XCTAssertEqual(obj->relation_id("child", 2).stable(), 987);

    obj->remove_relation_id("child", db::make_stable_id(db::value{654}));

    XCTAssertEqual(obj->relation_size("child"), 2);
    XCTAssertEqual(obj->relation_id("child", 0).stable(), 321);
    XCTAssertEqual(obj->relation_id("child", 1).stable(), 987);

    obj->remove_relation_at("child", 0);

    XCTAssertEqual(obj->relation_size("child"), 1);
    XCTAssertEqual(obj->relation_id("child", 0).stable(), 987);

    obj->remove_all_relations("child");

    XCTAssertEqual(obj->relation_size("child"), 0);
}

- (void)test_add_and_remove_relation_object {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));
    auto obj_b1 = db::object::make_shared(model.entity("sample_b"));
    auto obj_b2 = db::object::make_shared(model.entity("sample_b"));
    auto obj_b3 = db::object::make_shared(model.entity("sample_b"));

    obj_b1->manageable().load_data({.object_id = db::make_stable_id(db::value{5})});
    obj_b2->manageable().load_data({.object_id = db::make_stable_id(db::value{6})});
    obj_b3->manageable().load_data({.object_id = db::make_stable_id(db::value{7})});

    obj->add_relation_object("child", obj_b1);

    XCTAssertEqual(obj->relation_ids("child").size(), 1);

    obj->add_relation_object("child", obj_b2);

    XCTAssertEqual(obj->relation_ids("child").size(), 2);

    obj->add_relation_object("child", obj_b3);

    XCTAssertEqual(obj->relation_ids("child").size(), 3);

    XCTAssertEqual(obj->relation_size("child"), 3);

    XCTAssertEqual(obj->relation_ids("child").at(0).stable(), 5);
    XCTAssertEqual(obj->relation_ids("child").at(1).stable(), 6);
    XCTAssertEqual(obj->relation_ids("child").at(2).stable(), 7);
    XCTAssertEqual(obj->relation_id("child", 0).stable(), 5);
    XCTAssertEqual(obj->relation_id("child", 1).stable(), 6);
    XCTAssertEqual(obj->relation_id("child", 2).stable(), 7);

    obj->remove_relation_object("child", obj_b2);

    XCTAssertEqual(obj->relation_size("child"), 2);
    XCTAssertEqual(obj->relation_id("child", 0).stable(), 5);
    XCTAssertEqual(obj->relation_id("child", 1).stable(), 7);

    obj->remove_relation_at("child", 0);

    XCTAssertEqual(obj->relation_size("child"), 1);
    XCTAssertEqual(obj->relation_id("child", 0).stable(), 7);

    obj->remove_all_relations("child");

    XCTAssertEqual(obj->relation_size("child"), 0);
}

- (void)test_insert_relation_id {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));
    auto obj_b1 = db::object::make_shared(model.entity("sample_b"));
    auto obj_b2 = db::object::make_shared(model.entity("sample_b"));
    auto obj_b3 = db::object::make_shared(model.entity("sample_b"));
    obj_b1->manageable().load_data({.object_id = db::make_stable_id(db::value{5})});
    obj_b2->manageable().load_data({.object_id = db::make_stable_id(db::value{6})});
    obj_b3->manageable().load_data({.object_id = db::make_stable_id(db::value{7})});

    obj->insert_relation_id("child", obj_b1->object_id(), 0);

    XCTAssertEqual(obj->relation_ids("child").size(), 1);

    obj->insert_relation_id("child", obj_b2->object_id(), 1);

    XCTAssertEqual(obj->relation_ids("child").size(), 2);

    obj->insert_relation_id("child", obj_b3->object_id(), 0);

    XCTAssertEqual(obj->relation_ids("child").size(), 3);

    XCTAssertEqual(obj->relation_id("child", 0).stable(), 7);
    XCTAssertEqual(obj->relation_id("child", 1).stable(), 5);
    XCTAssertEqual(obj->relation_id("child", 2).stable(), 6);
}

- (void)test_insert_relation_object {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));
    auto obj_b1 = db::object::make_shared(model.entity("sample_b"));
    auto obj_b2 = db::object::make_shared(model.entity("sample_b"));
    auto obj_b3 = db::object::make_shared(model.entity("sample_b"));
    obj_b1->manageable().load_data({.object_id = db::make_stable_id(db::value{5})});
    obj_b2->manageable().load_data({.object_id = db::make_stable_id(db::value{6})});
    obj_b3->manageable().load_data({.object_id = db::make_stable_id(db::value{7})});

    obj->insert_relation_object("child", obj_b1, 0);

    XCTAssertEqual(obj->relation_ids("child").size(), 1);

    obj->insert_relation_object("child", obj_b2, 1);

    XCTAssertEqual(obj->relation_ids("child").size(), 2);

    obj->insert_relation_object("child", obj_b3, 0);

    XCTAssertEqual(obj->relation_ids("child").size(), 3);

    XCTAssertEqual(obj->relation_id("child", 0).stable(), 7);
    XCTAssertEqual(obj->relation_id("child", 1).stable(), 5);
    XCTAssertEqual(obj->relation_id("child", 2).stable(), 6);
}

- (void)test_replace_value {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    obj->set_attribute_value("age", db::value{1});

    XCTAssertEqual(obj->attribute_value("age"), db::value{1});

    obj->set_attribute_value("age", db::value{5});

    XCTAssertEqual(obj->attribute_value("age"), db::value{5});
}

- (void)test_remove {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    XCTAssertFalse(obj->is_removed());

    obj->manageable().load_data({.object_id = db::make_stable_id(db::value{45})});
    obj->set_attribute_value(db::pk_id_field, db::value{11});
    obj->set_attribute_value("name", db::value{"tanaka"});
    obj->set_relation_ids("child", {db::make_stable_id(db::value{111})});

    XCTAssertEqual(obj->object_id().stable_value(), db::value{45});
    XCTAssertEqual(obj->attribute_value("name"), db::value{"tanaka"});
    XCTAssertEqual(obj->relation_ids("child").at(0).stable(), 111);

    obj->remove();

    XCTAssertTrue(obj->is_removed());
    XCTAssertFalse(obj->attribute_value("name"));
    XCTAssertEqual(obj->attribute_value(db::pk_id_field), db::value{11});
    XCTAssertEqual(obj->object_id().stable_value(), db::value{45});
    XCTAssertEqual(obj->relation_ids("child").size(), 0);
}

- (void)test_action {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));
    auto manageable_obj = obj->manageable();

    XCTAssertEqual(obj->action(), db::null_value());

    db::object_data obj_data{.object_id = db::make_stable_id(db::value{0}),
                             .attributes = db::value_map_t{std::make_pair(db::action_field, db::insert_action_value())},
                             .relations = db::id_vector_map_t{std::make_pair(
                                 "child", db::id_vector_t{db::make_stable_id(12), db::make_stable_id(34)})}};
    obj->manageable().load_data(obj_data);
    XCTAssertEqual(obj->action(), db::insert_action_value());

    obj->set_attribute_value("name", db::value{"test_name"});
    XCTAssertEqual(obj->action(), db::update_action_value());

    manageable_obj.set_status(db::object_status::updating);
    obj->manageable().load_data(obj_data);
    XCTAssertEqual(obj->action(), db::insert_action_value());

    obj->add_relation_id("child", db::make_stable_id(db::value{2}));
    XCTAssertEqual(obj->action(), db::update_action_value());

    manageable_obj.set_status(db::object_status::updating);
    obj->manageable().load_data(obj_data);
    XCTAssertEqual(obj->action(), db::insert_action_value());

    obj->set_relation_ids("child", {db::make_stable_id(db::value{1})});
    XCTAssertEqual(obj->action(), db::update_action_value());

    manageable_obj.set_status(db::object_status::updating);
    obj->manageable().load_data(obj_data);
    XCTAssertEqual(obj->action(), db::insert_action_value());

    obj->remove_relation_at("child", 0);
    XCTAssertEqual(obj->action(), db::update_action_value());

    manageable_obj.set_status(db::object_status::updating);
    obj->manageable().load_data(obj_data);
    XCTAssertEqual(obj->action(), db::insert_action_value());

    obj->remove_all_relations("child");
    XCTAssertEqual(obj->action(), db::update_action_value());

    manageable_obj.set_status(db::object_status::updating);
    obj->manageable().load_data(obj_data);
    XCTAssertEqual(obj->action(), db::insert_action_value());

    obj->remove();
    XCTAssertEqual(obj->action(), db::remove_action_value());
    XCTAssertTrue(obj->is_removed());
}

- (void)test_save_data {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    obj->manageable().load_data({.object_id = db::make_stable_id(db::value{55})});
    obj->set_attribute_value(db::pk_id_field, db::value{22});
    obj->set_attribute_value("name", db::value{"suzuki"});
    obj->set_attribute_value("age", db::value{32});
    obj->set_attribute_value("weight", db::value{90.1});
    obj->set_attribute_value("data", db::null_value());
    obj->set_attribute_value(db::save_id_field, db::value{100});

    obj->set_relation_ids("child",
                         db::id_vector_t{db::make_stable_id(db::value{33}), db::make_stable_id(db::value{44})});

    db::object_id_pool obj_id_pool;

    auto data = obj->save_data(obj_id_pool);

    XCTAssertGreaterThan(data.attributes.size(), 6);
    XCTAssertEqual(data.attributes.count(db::pk_id_field), 1);
    XCTAssertEqual(data.attributes.at(db::pk_id_field), db::value{22});
    XCTAssertEqual(data.attributes.count(db::object_id_field), 1);
    XCTAssertEqual(data.attributes.at(db::object_id_field), db::value{55});
    XCTAssertEqual(data.attributes.count(db::action_field), 1);
    XCTAssertEqual(data.attributes.at(db::action_field), db::update_action_value());
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
    XCTAssertEqual(data.relations.at("child").at(0).stable_value(), db::value{33});
    XCTAssertEqual(data.relations.at("child").at(1).stable_value(), db::value{44});

    XCTAssertEqual(data.attributes.count(db::save_id_field), 0);
}

- (void)test_object_id_of_save_data {
    // save_dataで返されるobject_idが共通になっているか
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj_a = db::object::make_shared(model.entity("sample_a"));
    obj_a->manageable().load_data({.object_id = db::make_stable_id(100)});

    auto obj_b = db::object::make_shared(model.entity("sample_b"));
    obj_b->manageable().load_data({.object_id = db::make_stable_id(200)});

    obj_a->add_relation_object("child", obj_b);

    db::object_id_pool obj_id_pool;

    db::object_data save_data_a = obj_a->save_data(obj_id_pool);
    db::object_data save_data_b = obj_b->save_data(obj_id_pool);

    db::object_id const &rel_b_id = save_data_a.relations.at("child").at(0);
    db::object_id const &obj_b_id = save_data_b.object_id;

    XCTAssertEqual(rel_b_id, obj_b_id);
    XCTAssertEqual(rel_b_id.identifier(), obj_b_id.identifier());
}

- (void)test_save_data_same_object_id {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj_a1 = db::object::make_shared(model.entity("sample_a"));
    obj_a1->manageable().load_data({.object_id = db::make_stable_id(db::value{10})});
    obj_a1->set_relation_ids("child", db::id_vector_t{db::make_stable_id(db::value{10})});

    auto obj_a2 = db::object::make_shared(model.entity("sample_a"));
    obj_a2->manageable().load_data({.object_id = db::make_stable_id(db::value{20})});
    obj_a2->set_relation_ids("child", db::id_vector_t{db::make_stable_id(db::value{10})});

    auto obj_b = db::object::make_shared(model.entity("sample_b"));
    obj_b->manageable().load_data({.object_id = db::make_stable_id(db::value{10})});

    db::object_id_pool pool;

    auto save_data_a1 = obj_a1->save_data(pool);
    auto save_data_a2 = obj_a2->save_data(pool);
    auto save_data_b = obj_b->save_data(pool);

    // 同じエンティティの同じobject_idは同じもの
    XCTAssertEqual(save_data_b.object_id.identifier(), save_data_a1.relations.at("child").at(0).identifier());
    XCTAssertEqual(save_data_a1.relations.at("child").at(0).identifier(),
                   save_data_a2.relations.at("child").at(0).identifier());
    // 違うエンティティの同じobject_idは違うもの
    XCTAssertNotEqual(save_data_a1.object_id.identifier(), save_data_b.object_id.identifier());
}

- (void)test_change_status {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    auto manageable_obj = obj->manageable();

    XCTAssertEqual(obj->status(), db::object_status::invalid);

    manageable_obj.set_status(db::object_status::created);

    XCTAssertEqual(obj->status(), db::object_status::created);

    manageable_obj.set_status(db::object_status::saved);

    XCTAssertEqual(obj->status(), db::object_status::saved);

    manageable_obj.set_status(db::object_status::changed);

    XCTAssertEqual(obj->status(), db::object_status::changed);

    manageable_obj.set_status(db::object_status::updating);

    XCTAssertEqual(obj->status(), db::object_status::updating);
}

- (void)test_chain_attribute_updated_event {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));

    bool called = false;

    chaining::any_observer_ptr observer = obj->chain()
                                          .perform([&called, self](db::object_event const &event) {
                                              XCTAssertEqual(event.type(), db::object_event_type::attribute_updated);

                                              auto const &attr_event = event.get<db::object_attribute_updated_event>();

                                              XCTAssertEqual(attr_event.name, "name");
                                              XCTAssertEqual(attr_event.value, db::value{"test_value"});

                                              called = true;
                                          })
                                          .end();

    obj->set_attribute_value("name", db::value{"test_value"});

    XCTAssertTrue(called);
}

- (void)test_no_observe_chain_attribute_updated_with_same_value {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));

    bool called = false;

    obj->set_attribute_value("name", db::value{"test_value"});

    chaining::any_observer_ptr observer = obj->chain().perform([&called, self](auto const &) { called = true; }).end();

    obj->set_attribute_value("name", db::value{"test_value"});

    XCTAssertFalse(called);
}

- (void)test_chain_relation {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));

    size_t called_count = 0;

    chaining::any_observer_ptr observer =
        obj->chain()
            .perform([&called_count, self, weak_obj = to_weak(obj)](db::object_event const &event) {
                auto const obj = weak_obj.lock();

                if (called_count == 0) {
                    XCTAssertEqual(event.type(), db::object_event_type::relation_replaced);

                    auto const &replaced_event = event.get<db::object_relation_replaced_event>();
                    auto const name = replaced_event.name;

                    XCTAssertEqual(name, "child");
                    XCTAssertEqual(obj->relation_size(name), 2);
                    XCTAssertEqual(obj->relation_id(name, 0).stable(), 10);
                    XCTAssertEqual(obj->relation_id(name, 1).stable(), 20);
                } else if (called_count == 1) {
                    XCTAssertEqual(event.type(), db::object_event_type::relation_inserted);

                    auto const &inserted_event = event.get<db::object_relation_inserted_event>();
                    auto const name = inserted_event.name;

                    XCTAssertEqual(obj->relation_size(name), 3);
                    XCTAssertEqual(obj->relation_id(name, 2).stable(), 30);
                    XCTAssertEqual(inserted_event.indices.size(), 1);
                } else if (called_count == 2) {
                    XCTAssertEqual(event.type(), db::object_event_type::relation_removed);

                    auto const &removed_event = event.get<db::object_relation_removed_event>();
                    auto const name = removed_event.name;

                    XCTAssertEqual(obj->relation_size(name), 2);
                    XCTAssertEqual(obj->relation_id(name, 0).stable(), 10);
                    XCTAssertEqual(obj->relation_id(name, 1).stable(), 30);
                    XCTAssertEqual(removed_event.indices.size(), 1);
                } else if (called_count == 3) {
                    XCTAssertEqual(event.type(), db::object_event_type::relation_removed);

                    auto const &removed_event = event.get<db::object_relation_removed_event>();
                    auto const name = removed_event.name;

                    XCTAssertEqual(obj->relation_size(name), 0);
                    XCTAssertEqual(removed_event.indices.size(), 2);
                }

                ++called_count;
            })
            .end();

    obj->set_relation_ids("child",
                         db::id_vector_t{db::make_stable_id(db::value{10}), db::make_stable_id(db::value{20})});

    XCTAssertEqual(called_count, 1);

    obj->add_relation_id("child", db::make_stable_id(db::value{30}));

    XCTAssertEqual(called_count, 2);

    obj->remove_relation_id("child", db::make_stable_id(db::value{20}));

    XCTAssertEqual(called_count, 3);

    obj->remove_all_relations("child");

    XCTAssertEqual(called_count, 4);
}

- (void)test_no_observe_chain_relation_ids_with_same_value {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));

    obj->set_relation_ids("child", {db::make_stable_id(db::value{55})});

    bool called = false;

    chaining::any_observer_ptr observer = obj->chain().perform([&called, self](auto const &) { called = true; }).end();

    obj->set_relation_ids("child", {db::make_stable_id(db::value{55})});

    XCTAssertFalse(called);
}

- (void)test_chain_loaded {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));

    bool called = false;

    chaining::any_observer_ptr observer = obj->chain()
                                          .perform([&called, self](db::object_event const &event) {
                                              XCTAssertEqual(event.type(), db::object_event_type::loaded);

                                              auto const loaded_event = event.get<db::object_loaded_event>();
                                              auto const &obj = loaded_event.object;

                                              XCTAssertEqual(obj->object_id().stable_value(), db::value{1});

                                              XCTAssertEqual(obj->attribute_value("age"), db::value{10});
                                              XCTAssertEqual(obj->attribute_value("name"), db::value{"name_val"});
                                              XCTAssertEqual(obj->attribute_value("weight"), db::value{53.4});

                                              XCTAssertEqual(obj->relation_size("child"), 2);
                                              XCTAssertEqual(obj->relation_id("child", 0).stable(), 55);
                                              XCTAssertEqual(obj->relation_id("child", 1).stable(), 66);

                                              called = true;
                                          })
                                          .end();

    db::object_id obj_id = db::make_stable_id(db::value{1});
    db::value_map_t attributes{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                               std::make_pair("weight", db::value{53.4})};
    db::id_vector_map_t relations{
        std::make_pair("child", db::id_vector_t{db::make_stable_id(55), db::make_stable_id(66)})};
    db::object_data obj_data{
        .object_id = std::move(obj_id), .attributes = std::move(attributes), .relations = std::move(relations)};

    obj->manageable().load_data(obj_data);

    XCTAssertTrue(called);
}

- (void)test_clear {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));

    obj->set_attribute_value("age", db::value{20});
    obj->set_attribute_value("name", db::value{"test_name"});
    obj->set_relation_ids("child", {db::make_stable_id(db::value{23}), db::make_stable_id(db::value{45})});

    XCTAssertEqual(obj->status(), db::object_status::changed);

    XCTAssertEqual(obj->attribute_value("age"), db::value{20});
    XCTAssertEqual(obj->attribute_value("name"), db::value{"test_name"});
    XCTAssertEqual(obj->relation_id("child", 0).stable(), 23);
    XCTAssertEqual(obj->relation_id("child", 1).stable(), 45);

    obj->manageable().clear_data();

    XCTAssertEqual(obj->status(), db::object_status::invalid);

    XCTAssertFalse(obj->attribute_value("age"));
    XCTAssertFalse(obj->attribute_value("name"));
    XCTAssertEqual(obj->relation_size("child"), 0);
}

- (void)test_chain_cleared {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));

    obj->set_attribute_value("name", db::value{"test_name"});
    obj->set_relation_ids("child", {db::make_stable_id(db::value{101}), db::make_stable_id(db::value{102})});

    XCTAssertEqual(obj->status(), db::object_status::changed);

    bool called = false;

    chaining::any_observer_ptr observer = obj->chain()
                                          .perform([&called, self](db::object_event const &event) {
                                              XCTAssertEqual(event.type(), db::object_event_type::cleared);

                                              auto const cleared_event = event.get<db::object_cleared_event>();
                                              auto const &obj = cleared_event.object;

                                              XCTAssertEqual(obj->status(), db::object_status::invalid);
                                              XCTAssertFalse(obj->attribute_value("name"));
                                              XCTAssertEqual(obj->relation_size("child"), 0);

                                              called = true;
                                          })
                                          .end();

    obj->manageable().clear_data();

    XCTAssertTrue(called);
}

- (void)test_move {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj = db::object::make_shared(model.entity("sample_a"));

    XCTAssertTrue(obj);

    auto obj2 = std::move(obj);

    XCTAssertTrue(obj2);
    XCTAssertFalse(obj);

    db::object_ptr obj3 = nullptr;

    obj3 = std::move(obj2);

    XCTAssertTrue(obj3);
    XCTAssertFalse(obj2);
}

- (void)test_const_move {
    db::model model = [yas_db_test_utils model_0_0_1];

    db::object_id obj_id = db::make_stable_id(db::value{0});
    db::value_map_t attributes{std::make_pair("age", db::value{10})};
    db::object_data obj_data{.object_id = std::move(obj_id), .attributes = std::move(attributes)};

    auto obj = db::const_object::make_shared(model.entity("sample_a"), obj_data);

    db::const_object_ptr obj2 = std::move(obj);

    XCTAssertTrue(obj2);
    XCTAssertFalse(obj);

    db::const_object_ptr obj3 = nullptr;

    obj3 = std::move(obj2);

    XCTAssertTrue(obj3);
    XCTAssertFalse(obj2);
}

- (void)test_object_status_to_string {
    XCTAssertEqual(to_string(db::object_status::invalid), "invalid");
    XCTAssertEqual(to_string(db::object_status::created), "inserted");
    XCTAssertEqual(to_string(db::object_status::saved), "saved");
    XCTAssertEqual(to_string(db::object_status::changed), "changed");
    XCTAssertEqual(to_string(db::object_status::updating), "updating");
}

- (void)test_is_inserted {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    obj->set_attribute_value(db::action_field, db::insert_action_value());

    XCTAssertTrue(obj->is_inserted());

    obj->set_attribute_value(db::action_field, db::update_action_value());

    XCTAssertFalse(obj->is_inserted());

    obj->set_attribute_value(db::action_field, db::remove_action_value());

    XCTAssertFalse(obj->is_inserted());
}

- (void)test_is_updated {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    obj->set_attribute_value(db::action_field, db::update_action_value());

    XCTAssertTrue(obj->is_updated());

    obj->set_attribute_value(db::action_field, db::insert_action_value());

    XCTAssertFalse(obj->is_updated());

    obj->set_attribute_value(db::action_field, db::remove_action_value());

    XCTAssertFalse(obj->is_updated());
}

- (void)test_is_removed {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    obj->set_attribute_value(db::action_field, db::remove_action_value());

    XCTAssertTrue(obj->is_removed());

    obj->set_attribute_value(db::action_field, db::insert_action_value());

    XCTAssertFalse(obj->is_removed());

    obj->set_attribute_value(db::action_field, db::update_action_value());

    XCTAssertFalse(obj->is_removed());
}

- (void)test_action_values {
    XCTAssertEqual(db::insert_action_value().get<db::text>(), db::insert_action);
    XCTAssertEqual(db::update_action_value().get<db::text>(), db::update_action);
    XCTAssertEqual(db::remove_action_value().get<db::text>(), db::remove_action);
}

- (void)test_fetched_event {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto obj = db::object::make_shared(model.entity("sample_a"));

    bool called = false;

    auto chain = obj->chain()
                     .perform([&called](db::object_event const &event) {
                         if (event.type() == db::object_event_type::fetched) {
                             called = true;
                         }
                     })
                     .sync();

    XCTAssertTrue(called);
}

@end
