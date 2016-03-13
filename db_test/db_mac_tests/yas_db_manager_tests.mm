//
//  yas_db_manager_tests.mm
//

#import "yas_db_test_utils.h"
#import "yas_db_utils.h"

using namespace yas;

@interface yas_db_manager_tests : XCTestCase

@end

@implementation yas_db_manager_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_create {
    auto db_path = [yas_db_test_utils database_path];
    db::manager manager{db_path, db::model{nullptr}};

    XCTAssertTrue(manager);
    XCTAssertEqual(manager.database_path(), db_path);
}

- (void)test_execute_in_bg {
    auto manager = [yas_db_test_utils create_test_manager];

    XCTestExpectation *exp = [self expectationWithDescription:@"execution"];

    manager.execute([self, exp](auto const &operation) {
        XCTAssertTrue(operation);
        XCTAssertFalse([NSThread isMainThread]);
        [exp fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_execute_update_and_query_in_bg {
    auto manager = [yas_db_test_utils create_test_manager];

    manager.execute([self, &manager](auto const &operation) {
        auto &db = manager.database();

        XCTAssertTrue(db.execute_update(db::create_table_sql("test_table", {"field_a", "field_b"})));

        db::value_vector args{db::value{"value_a"}, db::value{"value_b"}};
        XCTAssertTrue(db.execute_update("insert into test_table(field_a, field_b) values(:field_a, :field_b)", args));

        auto query_result = db.execute_query("select * from test_table");
        auto &row_set = query_result.value();

        XCTAssertTrue(row_set);
        XCTAssertTrue(row_set.next());

        XCTAssertEqual(row_set.column_value(0).get<db::text>(), "value_a");
        XCTAssertEqual(row_set.column_value(1).get<db::text>(), "value_b");

        XCTAssertFalse(row_set.next());
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_setup {
    db::model model{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.execute([self, &manager](auto const &op) {
        auto &db = manager.database();

        XCTAssertTrue(db::table_exists(db, db::info_table));
        auto select_infos_result = db::select(db, db::select_option{.table = db::info_table});
        XCTAssertTrue(select_infos_result);
        XCTAssertEqual(select_infos_result.value().size(), 1);
        XCTAssertEqual(select_infos_result.value().at(0).at(db::version_field).get<db::text>(), "0.0.1");

        XCTAssertTrue(db::table_exists(db, "sample_a"));
        auto select_result_a = db::select(db, db::select_option{.table = "sample_a"});
        XCTAssertTrue(select_result_a);
        XCTAssertEqual(select_result_a.value().size(), 0);

        XCTAssertTrue(db::table_exists(db, "rel_sample_a_child"));
        auto select_rels_result = db::select(db, db::select_option{.table = "rel_sample_a_child"});
        XCTAssertTrue(select_rels_result);
        XCTAssertEqual(select_rels_result.value().size(), 0);

        XCTAssertTrue(db::index_exists(db, "sample_a_name"));
        XCTAssertTrue(db::index_exists(db, "sample_a_others"));
        XCTAssertFalse(db::index_exists(db, "sample_b_name"));

    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_insert_object {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    db::object_vector objects;

    manager.setup([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);

        objects.emplace_back(manager.insert_object("sample_a"));
        objects.emplace_back(manager.insert_object("sample_a"));

        for (auto const &idx : each_index<std::size_t>(2)) {
            auto const &object = objects[idx];

            XCTAssertEqual(object.status(), db::object_status::inserted);
            XCTAssertEqual(object.get_attribute(db::action_field), db::value{db::insert_action});
            XCTAssertEqual(object.get_attribute("name"), db::value{"default_value"});
            XCTAssertEqual(object.get_attribute("age"), db::value{10});
            XCTAssertEqual(object.get_attribute("weight"), db::value{65.4});

            XCTAssertFalse(object.get_attribute(db::id_field));
            XCTAssertEqual(object.get_attribute(db::object_id_field), db::value{0});
            XCTAssertEqual(object.get_attribute(db::save_id_field), db::value{0});
        }

        objects[0].set_attribute("name", db::value{"test_name_0_inserted"});
        objects[1].set_attribute("name", db::value{"test_name_1_inserted"});

        XCTAssertEqual(objects[0].status(), db::object_status::inserted);
        XCTAssertEqual(objects[1].status(), db::object_status::inserted);

        XCTAssertTrue(manager.has_inserted_objects());
        XCTAssertEqual(manager.inserted_object_count("sample_a"), 2);
    });

    manager.save([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{1});

        auto &a_objects = result.value().at("sample_a");
        XCTAssertEqual(a_objects.size(), 2);

        for (auto const &idx : each_index<std::size_t>(2)) {
            auto &object = objects.at(idx);
            auto &saved_object = a_objects.at(idx);

            XCTAssertEqual(saved_object, object);

            XCTAssertEqual(saved_object.status(), db::object_status::saved);
            XCTAssertEqual(saved_object.get_attribute(db::action_field), db::value{db::insert_action});
            XCTAssertEqual(saved_object.get_attribute("age"), db::value{10});
            XCTAssertEqual(saved_object.get_attribute("weight"), db::value{65.4});

            XCTAssertEqual(saved_object.get_attribute(db::save_id_field), db::value{1});
        }

        XCTAssertEqual(a_objects.at(0).get_attribute("name"), db::value{"test_name_0_inserted"});
        XCTAssertEqual(a_objects.at(1).get_attribute("name"), db::value{"test_name_1_inserted"});
        XCTAssertEqual(a_objects.at(0).get_attribute(db::object_id_field), db::value{1});
        XCTAssertEqual(a_objects.at(1).get_attribute(db::object_id_field), db::value{2});

        XCTAssertFalse(manager.has_inserted_objects());
        XCTAssertEqual(manager.inserted_object_count("sample_a"), 0);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_insert_and_save_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    db::object_vector objects{};

    manager.setup([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);

        objects.emplace_back(manager.insert_object("sample_a"));
        objects.emplace_back(manager.insert_object("sample_a"));

        objects[0].set_attribute("name", db::value{"test_name_0_inserted"});
        objects[1].set_attribute("name", db::value{"test_name_1_inserted"});

        XCTAssertTrue(manager.has_inserted_objects());
        XCTAssertEqual(manager.inserted_object_count("sample_a"), 2);
    });

    manager.save([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertFalse(manager.has_inserted_objects());

        XCTAssertEqual(objects[0].status(), db::object_status::saved);
        XCTAssertEqual(objects[1].status(), db::object_status::saved);
        XCTAssertTrue(manager.cached_object("sample_a", objects[0].object_id().get<db::integer>()));
        XCTAssertTrue(manager.cached_object("sample_a", objects[1].object_id().get<db::integer>()));

        objects[0].set_attribute("name", db::value{"test_name_0_saved"});
        objects[1].set_attribute("name", db::value{"test_name_1_saved"});

        XCTAssertEqual(objects[0].status(), db::object_status::changed);
        XCTAssertEqual(objects[1].status(), db::object_status::changed);

        XCTAssertTrue(manager.has_changed_objects());
        XCTAssertEqual(manager.changed_object_count("sample_a"), 2);
        XCTAssertFalse(manager.has_inserted_objects());
        XCTAssertEqual(manager.inserted_object_count("sample_a"), 0);

        objects.emplace_back(manager.insert_object("sample_a"));
        objects.emplace_back(manager.insert_object("sample_a"));

        objects[2].set_attribute("name", db::value{"test_name_2_inserted"});
        objects[3].set_attribute("name", db::value{"test_name_3_inserted"});

        XCTAssertTrue(manager.has_inserted_objects());
    });

    manager.save([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);

        XCTAssertEqual(objects[0].get_attribute("name"), db::value{"test_name_0_saved"});
        XCTAssertEqual(objects[1].get_attribute("name"), db::value{"test_name_1_saved"});
        XCTAssertEqual(objects[2].get_attribute("name"), db::value{"test_name_2_inserted"});
        XCTAssertEqual(objects[3].get_attribute("name"), db::value{"test_name_3_inserted"});

        XCTAssertEqual(objects[0].status(), db::object_status::saved);
        XCTAssertEqual(objects[1].status(), db::object_status::saved);
        XCTAssertEqual(objects[2].status(), db::object_status::saved);
        XCTAssertEqual(objects[3].status(), db::object_status::saved);

        XCTAssertEqual(objects[0].object_id(), db::value{1});
        XCTAssertEqual(objects[1].object_id(), db::value{2});
        XCTAssertEqual(objects[2].object_id(), db::value{3});
        XCTAssertEqual(objects[3].object_id(), db::value{4});
    });

    manager.fetch_const_objects(
        []() {
            return db::select_option{
                .table = "sample_a",
                .field_orders = {db::field_order{.field = db::object_id_field, .order = db::order::ascending}}};
        },
        [self, &manager](auto result) {
            XCTAssertTrue(result);

            db::const_object_vector &objects = result.value().at("sample_a");
            XCTAssertEqual(objects.size(), 4);

            XCTAssertEqual(objects[0].get_attribute("name"), db::value{"test_name_0_saved"});
            XCTAssertEqual(objects[1].get_attribute("name"), db::value{"test_name_1_saved"});
            XCTAssertEqual(objects[2].get_attribute("name"), db::value{"test_name_2_inserted"});
            XCTAssertEqual(objects[3].get_attribute("name"), db::value{"test_name_3_inserted"});
        });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_set_relation_to_inserted_object {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);

        auto object_a = manager.insert_object("sample_a");
        auto object_b = manager.insert_object("sample_b");

        XCTAssertThrows(object_a.set_relation_object("child", {object_b}));
        XCTAssertThrows(object_a.push_back_relation_object("child", object_b));
    });

    manager.save([self](auto result) {
        XCTAssertTrue(result);

        db::object &object_a = result.value().at("sample_a").at(0);
        auto &object_b = result.value().at("sample_b").at(0);

        XCTAssertNoThrow(object_a.set_relation_object("child", {object_b}));
        XCTAssertEqual(object_a.get_relation_object("child", 0), object_b);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_setup_migration {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.execute([self, &manager](auto const &) {
        auto &db = manager.database();

        db::begin_transaction(db);

        bool rollback = false;

        if (!db.execute_update(db::insert_sql("sample_a", {"age", "name", "weight"}),
                               {db::value{2}, db::value{"xyz"}, db::value{451.2}})) {
            rollback = true;
        }

        if (!db.execute_update(db::insert_sql("sample_b", {"name"}), {db::value{"qwerty"}})) {
            rollback = true;
        }

        db::select_option option_a{.table = "sample_a", .fields = {db::id_field}};
        auto select_result_a = db::select(db, option_a);
        auto &src_id = select_result_a.value().at(0).at(db::id_field);

        db::select_option option_b{.table = "sample_b", .fields = {db::id_field}};
        auto select_result_b = db::select(db, option_b);
        auto &tgt_id = select_result_b.value().at(0).at(db::id_field);

        auto sql = db::insert_sql("rel_sample_a_child", {db::src_obj_id_field, db::tgt_obj_id_field});
        if (!db.execute_update(sql, db::value_vector{src_id, tgt_id})) {
            rollback = true;
        }

        db::value const save_id{100};
        if (!db.execute_update(db::update_sql(db::info_table, {db::current_save_id_field, db::last_save_id_field}, ""),
                               db::value_vector{save_id, save_id})) {
            rollback = true;
        }

        XCTAssertFalse(rollback);

        if (rollback) {
            db::rollback(db);
        } else {
            db::commit(db);
        }
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    manager = nullptr;

    db::model model_0_0_2{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_2]};
    manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.execute([self, &manager](auto const &) {
        auto &db = manager.database();

        XCTAssertTrue(db::table_exists(db, db::info_table));
        auto select_infos_result = db::select(db, db::select_option{.table = db::info_table});
        XCTAssertTrue(select_infos_result);
        XCTAssertEqual(select_infos_result.value().size(), 1);
        XCTAssertEqual(select_infos_result.value().at(0).at(db::version_field).get<db::text>(), "0.0.2");
        XCTAssertEqual(select_infos_result.value().at(0).at(db::current_save_id_field).get<db::integer>(), 100);
        XCTAssertEqual(select_infos_result.value().at(0).at(db::last_save_id_field).get<db::integer>(), 100);

        XCTAssertTrue(db::table_exists(db, "sample_a"));
        auto select_result_a = db::select(db, db::select_option{.table = "sample_a"});
        XCTAssertTrue(select_result_a);
        XCTAssertEqual(select_result_a.value().size(), 1);

        auto const &sample_a = select_result_a.value().at(0);
        XCTAssertEqual(sample_a.at("age").get<db::integer>(), 2);
        XCTAssertEqual(sample_a.at("name").get<db::text>(), "xyz");
        XCTAssertEqual(sample_a.at("weight").get<db::real>(), 451.2);

        XCTAssertTrue(db::table_exists(db, "sample_b"));
        auto select_result_b = db::select(db, db::select_option{.table = "sample_b"});
        XCTAssertTrue(select_result_b);
        XCTAssertEqual(select_result_b.value().size(), 1);

        auto const &sample_b = select_result_b.value().at(0);
        XCTAssertEqual(sample_b.at("name").get<db::text>(), "qwerty");

        XCTAssertTrue(db::table_exists(db, "sample_c"));
        auto select_result_c = db::select(db, db::select_option{.table = "sample_c"});
        XCTAssertTrue(select_result_c);
        XCTAssertEqual(select_result_c.value().size(), 0);

        XCTAssertTrue(db::table_exists(db, "rel_sample_a_child"));
        auto select_rels_result = db::select(db, db::select_option{.table = "rel_sample_a_child"});
        XCTAssertEqual(select_rels_result.value().size(), 1);

        auto &src_id = sample_a.at(db::id_field);
        auto &tgt_id = sample_b.at(db::id_field);

        auto &rel = select_rels_result.value().at(0);
        XCTAssertEqual(rel.at(db::src_obj_id_field), src_id);
        XCTAssertEqual(rel.at(db::tgt_obj_id_field), tgt_id);

        XCTAssertTrue(db::index_exists(db, "sample_a_name"));
        XCTAssertTrue(db::index_exists(db, "sample_a_others"));
        XCTAssertTrue(db::index_exists(db, "sample_b_name"));
    });

    exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_insert_objects_by_count {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *exp1 = [self expectationWithDescription:@"insert_1"];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
        XCTAssertEqual(manager.last_save_id(), db::value{0});
    });

    db::object_vector_map inserted_objects_1;

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 3}};
        },
        [self, &manager, exp1, &inserted_objects_1](auto result) {
            XCTAssertTrue(result);

            inserted_objects_1 = std::move(result.value());
            XCTAssertGreaterThan(inserted_objects_1.count("sample_a"), 0);

            db::object_vector const &objects = inserted_objects_1.at("sample_a");
            XCTAssertEqual(objects.size(), 3);

            XCTAssertEqual(objects.at(0).object_id(), db::value{1});
            XCTAssertEqual(objects.at(1).object_id(), db::value{2});
            XCTAssertEqual(objects.at(2).object_id(), db::value{3});

            XCTAssertEqual(objects.at(0).save_id(), db::value{1});
            XCTAssertEqual(objects.at(1).save_id(), db::value{1});
            XCTAssertEqual(objects.at(2).save_id(), db::value{1});

            XCTAssertEqual(objects.at(0).action(), db::value{db::insert_action});
            XCTAssertEqual(objects.at(1).action(), db::value{db::insert_action});
            XCTAssertEqual(objects.at(2).action(), db::value{db::insert_action});

            XCTAssertEqual(objects.at(0).manager(), manager);
            XCTAssertEqual(objects.at(1).manager(), manager);
            XCTAssertEqual(objects.at(2).manager(), manager);

            [exp1 fulfill];
        });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(inserted_objects_1.size(), 1);
    XCTAssertGreaterThan(inserted_objects_1.count("sample_a"), 0);
    XCTAssertEqual(inserted_objects_1.at("sample_a").size(), 3);

    XCTAssertEqual(manager.current_save_id(), db::value{1});
    XCTAssertEqual(manager.last_save_id(), db::value{1});

    XCTestExpectation *exp2 = [self expectationWithDescription:@"insert_2"];

    db::object_vector_map inserted_objects_2;

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, exp2, &manager, &inserted_objects_2](auto result) {
            XCTAssertTrue(result);

            inserted_objects_2 = std::move(result.value());
            db::object_vector const &objects = inserted_objects_2.at("sample_a");

            XCTAssertEqual(objects.size(), 1);

            XCTAssertEqual(objects.at(0).object_id(), db::value{4});
            XCTAssertEqual(objects.at(0).save_id(), db::value{2});
            XCTAssertEqual(objects.at(0).action(), db::value{db::insert_action});
            XCTAssertEqual(objects.at(0).manager(), manager);

            [exp2 fulfill];
        });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(inserted_objects_2.size(), 1);
    XCTAssertEqual(inserted_objects_2.count("sample_a"), 1);
    XCTAssertEqual(inserted_objects_2.at("sample_a").size(), 1);

    XCTAssertEqual(manager.current_save_id(), db::value{2});
    XCTAssertEqual(manager.last_save_id(), db::value{2});

    auto const object_1 = manager.cached_object("sample_a", 1);
    XCTAssertTrue(object_1);
    XCTAssertEqual(object_1.object_id(), db::value{1});

    XCTAssertFalse(manager.cached_object("sample_a", 5));
}

- (void)test_insert_objects_by_values {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
    });

    manager.insert_objects(
        []() {
            db::value_map obj1{{"name", db::value{"test_name_1"}}, {"age", db::value{43}}};
            db::value_map obj2{{"name", db::value{"test_name_2"}}, {"age", db::value{67}}};
            db::value_map_vector sample_as{std::move(obj1), std::move(obj2)};
            return db::value_map_vector_map{{"sample_a", std::move(sample_as)}};
        },
        [self, &manager](auto result) {
            XCTAssertTrue(result);

            auto &objects = result.value();

            XCTAssertEqual(objects.count("sample_a"), 1);

            auto &a_objects = objects.at("sample_a");

            XCTAssertEqual(a_objects.size(), 2);

            XCTAssertEqual(a_objects.at(0).get_attribute("name"), db::value{"test_name_1"});
            XCTAssertEqual(a_objects.at(0).get_attribute("age"), db::value{43});
            XCTAssertEqual(a_objects.at(1).get_attribute("name"), db::value{"test_name_2"});
            XCTAssertEqual(a_objects.at(1).get_attribute("age"), db::value{67});

            XCTAssertEqual(manager.current_save_id(), db::value{1});
        });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_insert_many_entity_objects {
    db::model model_0_0_2{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_2]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 3}, {"sample_b", 5}};
        },
        [self](auto result) {
            db::object_vector_map const &objects = result.value();
            XCTAssertEqual(objects.size(), 2);

            XCTAssertGreaterThan(objects.count("sample_a"), 0);

            db::object_vector const &a_objects = objects.at("sample_a");
            XCTAssertEqual(a_objects.size(), 3);

            XCTAssertGreaterThan(objects.count("sample_b"), 0);

            db::object_vector const &b_objects = objects.at("sample_b");
            XCTAssertEqual(b_objects.size(), 5);
        });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_insert_with_delete {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
        XCTAssertEqual(manager.last_save_id(), db::value{0});
    });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, &manager](auto result) {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{1});

            auto &objects = result.value();
            auto &object = objects.at("sample_a").at(0);
            XCTAssertEqual(object.save_id(), db::value{1});

            object.set_attribute("name", db::value{"first_name_value"});
        });

    manager.save([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{2});
    });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, &manager](auto result) {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{3});

            auto &objects = result.value();
            auto &object = objects.at("sample_a").at(0);
            XCTAssertEqual(object.save_id(), db::value{3});

            object.set_attribute("name", db::value{"second_name_value"});
        });

    manager.save([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{4});

    });

    manager.revert([]() { return 2; },
                   [self, &manager](auto result) {
                       XCTAssertTrue(result);
                       XCTAssertEqual(manager.current_save_id(), db::value{2});
                   });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, &manager](auto result) {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{3});

            auto &objects = result.value();
            auto &object = objects.at("sample_a").at(0);
            XCTAssertEqual(object.save_id(), db::value{3});
        });

    manager.execute([self, &manager](operation const &op) {
        auto &db = manager.database();
        auto result = db::select(db, {.table = "sample_a"});

        auto &object_datas = result.value();
        XCTAssertEqual(object_datas.size(), 3);

        for (auto &object_data : object_datas) {
            XCTAssertNotEqual(object_data.at("name"), db::value{"second_name_value"});
        }
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_fetch_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];

    db::object_vector_map objects;

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 3}, {"sample_b", 2}};
        },
        [self, exp1, &objects](auto result) {
            XCTAssertTrue(result);

            objects = std::move(result.value());

            XCTAssertGreaterThan(objects.count("sample_a"), 0);
            auto &a_objects = objects.at("sample_a");
            XCTAssertEqual(a_objects.size(), 3);
            XCTAssertEqual(a_objects.at(0).object_id().get<db::integer>(), 1);
            XCTAssertEqual(a_objects.at(1).object_id().get<db::integer>(), 2);
            XCTAssertEqual(a_objects.at(2).object_id().get<db::integer>(), 3);
            XCTAssertEqual(a_objects.at(0).save_id().get<db::integer>(), 1);
            XCTAssertEqual(a_objects.at(1).save_id().get<db::integer>(), 1);
            XCTAssertEqual(a_objects.at(2).save_id().get<db::integer>(), 1);
            XCTAssertEqual(a_objects.at(0).get_attribute("name").get<db::text>(), "default_value");
            XCTAssertEqual(a_objects.at(1).get_attribute("name").get<db::text>(), "default_value");
            XCTAssertEqual(a_objects.at(2).get_attribute("name").get<db::text>(), "default_value");

            XCTAssertGreaterThan(objects.count("sample_b"), 0);
            auto &b_objects = objects.at("sample_b");
            XCTAssertEqual(b_objects.size(), 2);
            XCTAssertEqual(b_objects.at(0).object_id().get<db::integer>(), 1);
            XCTAssertEqual(b_objects.at(1).object_id().get<db::integer>(), 2);
            XCTAssertEqual(b_objects.at(0).save_id().get<db::integer>(), 1);
            XCTAssertEqual(b_objects.at(1).save_id().get<db::integer>(), 1);
            XCTAssertFalse(b_objects.at(0).get_attribute("name"));
            XCTAssertFalse(b_objects.at(1).get_attribute("name"));

            [exp1 fulfill];
        });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{1});
    XCTAssertEqual(manager.last_save_id(), db::value{1});
    objects.at("sample_a").at(1).set_attribute("name", db::value{"value_1"});
    objects.at("sample_a").at(1).push_back_relation_id("child", objects.at("sample_b").at(0).object_id());

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.save([self, exp2](auto save_result) {
        XCTAssertTrue(save_result);

        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{2});
    XCTAssertEqual(manager.last_save_id(), db::value{2});

    XCTestExpectation *exp3 = [self expectationWithDescription:@"3"];

    manager.fetch_objects([]() { return db::select_option{.table = "sample_a"}; },
                          [self, exp3](auto fetch_result) {
                              XCTAssertTrue(fetch_result);

                              auto const &objects = fetch_result.value();
                              XCTAssertGreaterThan(objects.count("sample_a"), 0);
                              auto &a_objects = objects.at("sample_a");
                              XCTAssertEqual(a_objects.size(), 3);
                              XCTAssertEqual(a_objects.at(0).object_id(), db::value{1});
                              XCTAssertEqual(a_objects.at(1).object_id(), db::value{3});
                              XCTAssertEqual(a_objects.at(2).object_id(), db::value{2});
                              XCTAssertEqual(a_objects.at(0).save_id(), db::value{1});
                              XCTAssertEqual(a_objects.at(1).save_id(), db::value{1});
                              XCTAssertEqual(a_objects.at(2).save_id(), db::value{2});
                              XCTAssertEqual(a_objects.at(0).get_attribute("name"), db::value{"default_value"});
                              XCTAssertEqual(a_objects.at(1).get_attribute("name"), db::value{"default_value"});
                              XCTAssertEqual(a_objects.at(2).get_attribute("name"), db::value{"value_1"});

                              XCTAssertEqual(a_objects.at(2).relation_size("child"), 1);
                              XCTAssertEqual(a_objects.at(2).get_relation_ids("child").size(), 1);
                              XCTAssertEqual(a_objects.at(2).get_relation_id("child", 0), db::value{1});

                              [exp3 fulfill];
                          });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    objects.at("sample_a").at(2).set_attribute("name", db::value{"value_2"});
    objects.at("sample_a").at(2).clear_relation("child");
    objects.at("sample_a").at(2).push_back_relation_id("child", objects.at("sample_b").at(1).object_id());
    objects.at("sample_a").at(2).push_back_relation_id("child", objects.at("sample_b").at(0).object_id());

    XCTestExpectation *exp4 = [self expectationWithDescription:@"4"];

    manager.save([self, exp4](auto save_result) { [exp4 fulfill]; });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{3});
    XCTAssertEqual(manager.last_save_id(), db::value{3});

    manager.fetch_objects(
        []() {
            return db::select_option{.table = "sample_a",
                                     .where_exprs = db::field_expr("name", "like"),
                                     .arguments = {{"name", db::value{"value_%"}}},
                                     .field_orders = {{db::object_id_field, db::order::descending}},
                                     .limit_range = db::range{0, 3}};
        },
        [self, &objects](auto fetch_result) {
            XCTAssertTrue(fetch_result);

            auto const &objects = fetch_result.value();
            XCTAssertGreaterThan(objects.count("sample_a"), 0);
            auto &a_objects = objects.at("sample_a");
            XCTAssertEqual(a_objects.size(), 2);

            XCTAssertEqual(a_objects.at(0).object_id(), db::value{3});
            XCTAssertEqual(a_objects.at(0).save_id(), db::value{3});
            XCTAssertEqual(a_objects.at(0).get_attribute("name"), db::value{"value_2"});

            XCTAssertEqual(a_objects.at(1).object_id(), db::value{2});
            XCTAssertEqual(a_objects.at(1).save_id(), db::value{2});
            XCTAssertEqual(a_objects.at(1).get_attribute("name"), db::value{"value_1"});

            XCTAssertEqual(a_objects.at(0).relation_size("child"), 2);
            XCTAssertEqual(a_objects.at(0).get_relation_ids("child").size(), 2);
            XCTAssertEqual(a_objects.at(0).get_relation_id("child", 0), db::value{2});
            XCTAssertEqual(a_objects.at(0).get_relation_id("child", 1), db::value{1});
        });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_fetch_const_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) mutable {
        XCTAssertTrue(result);

    });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}, {"sample_b", 1}};
        },
        [self, &manager](auto result) mutable {
            XCTAssertTrue(result);
            auto &objects = result.value();

            XCTAssertEqual(manager.current_save_id(), db::value{1});
            XCTAssertEqual(manager.last_save_id(), db::value{1});

            objects.at("sample_a").at(0).set_attribute("name", db::value{"value_0"});

            auto &object_b = objects.at("sample_b").at(0);
            objects.at("sample_a").at(0).push_back_relation_id("child", object_b.object_id());

            XCTAssertEqual(object_b.object_id(), db::value{1});

        });

    manager.save([self](auto save_result) { XCTAssertTrue(save_result); });

    manager.fetch_const_objects([]() { return db::select_option{.table = "sample_a"}; },
                                [self](db::manager::const_vector_result_t fetch_result) mutable {
                                    XCTAssertTrue(fetch_result);

                                    auto const &objects = fetch_result.value();
                                    XCTAssertGreaterThan(objects.count("sample_a"), 0);
                                    auto &a_objects = objects.at("sample_a");
                                    XCTAssertEqual(a_objects.size(), 1);
                                    XCTAssertEqual(a_objects.at(0).object_id().get<db::integer>(), 1);
                                    XCTAssertEqual(a_objects.at(0).save_id().get<db::integer>(), 2);
                                    XCTAssertEqual(a_objects.at(0).get_attribute("name"), db::value{"value_0"});

                                    XCTAssertEqual(a_objects.at(0).relation_size("child"), 1);
                                    XCTAssertEqual(a_objects.at(0).get_relation_ids("child").size(), 1);
                                    XCTAssertEqual(a_objects.at(0).get_relation_id("child", 0), db::value{1});
                                });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_fetch_relation_objects {
    db::model model_0_0_2{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_2]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}, {"sample_b", 1}, {"sample_c", 1}};
        },
        [self, exp1](auto result) {
            XCTAssertTrue(result);

            auto const &objects = result.value();
            XCTAssertEqual(objects.size(), 3);
            XCTAssertEqual(objects.count("sample_a"), 1);
            XCTAssertEqual(objects.count("sample_b"), 1);
            XCTAssertEqual(objects.count("sample_c"), 1);

            auto const &a_objects = objects.at("sample_a");
            XCTAssertEqual(a_objects.size(), 1);

            auto const &b_objects = objects.at("sample_b");
            XCTAssertEqual(b_objects.size(), 1);

            auto const &c_objects = objects.at("sample_c");
            XCTAssertEqual(c_objects.size(), 1);

            auto object_a = a_objects.at(0);
            auto object_b = b_objects.at(0);
            auto object_c = c_objects.at(0);

            object_a.push_back_relation_object("child", object_b);
            object_a.push_back_relation_object("friend", object_c);

            object_b.push_back_relation_object("parent", object_a);
            object_c.push_back_relation_object("friend", object_a);

            [exp1 fulfill];
        });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.save([self, exp2](auto save_result) {
        XCTAssertTrue(save_result);

        auto const &objects = save_result.value();

        XCTAssertEqual(objects.size(), 3);
        XCTAssertEqual(objects.at("sample_a").size(), 1);
        XCTAssertEqual(objects.at("sample_b").size(), 1);
        XCTAssertEqual(objects.at("sample_c").size(), 1);

        XCTAssertEqual(objects.at("sample_a").at(0).relation_size("child"), 1);
        XCTAssertEqual(objects.at("sample_a").at(0).get_relation_object("child", 0), objects.at("sample_b").at(0));
        XCTAssertEqual(objects.at("sample_a").at(0).get_relation_id("child", 0), db::value{1});
        XCTAssertEqual(objects.at("sample_a").at(0).relation_size("friend"), 1);
        XCTAssertEqual(objects.at("sample_a").at(0).get_relation_object("friend", 0), objects.at("sample_c").at(0));
        XCTAssertEqual(objects.at("sample_a").at(0).get_relation_id("friend", 0), db::value{1});

        XCTAssertEqual(objects.at("sample_b").at(0).relation_size("parent"), 1);
        XCTAssertEqual(objects.at("sample_b").at(0).get_relation_object("parent", 0), objects.at("sample_a").at(0));

        XCTAssertEqual(objects.at("sample_c").at(0).relation_size("friend"), 1);
        XCTAssertEqual(objects.at("sample_c").at(0).get_relation_object("friend", 0), objects.at("sample_a").at(0));

        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertFalse(manager.cached_object("sample_a", 1));
    XCTAssertFalse(manager.cached_object("sample_b", 1));
    XCTAssertFalse(manager.cached_object("sample_c", 1));

    XCTestExpectation *exp3 = [self expectationWithDescription:@"3"];

    db::object object_a{nullptr};

    manager.fetch_objects([]() { return db::select_option{.table = "sample_a"}; },
                          [self, exp3, &object_a](auto const &fetch_result) {
                              XCTAssertTrue(fetch_result);

                              auto const &objects = fetch_result.value();

                              XCTAssertEqual(objects.size(), 1);

                              object_a = objects.at("sample_a").at(0);
                              XCTAssertEqual(objects.at("sample_a").at(0).relation_size("child"), 1);
                              XCTAssertFalse(objects.at("sample_a").at(0).get_relation_object("child", 0));
                              XCTAssertEqual(objects.at("sample_a").at(0).relation_size("friend"), 1);
                              XCTAssertFalse(objects.at("sample_a").at(0).get_relation_object("friend", 0));

                              [exp3 fulfill];
                          });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    manager.fetch_objects(
        [object_a]() {
            return db::relation_ids(db::object_vector_map{std::make_pair("sample_a", db::object_vector{object_a})});
        },
        [self, object_a](auto const &fetch_result) {
            XCTAssertTrue(fetch_result);

            auto const &objects = fetch_result.value();

            XCTAssertEqual(objects.size(), 2);
            XCTAssertEqual(objects.count("sample_b"), 1);
            XCTAssertEqual(objects.count("sample_c"), 1);

            XCTAssertEqual(objects.at("sample_b").size(), 1);
            XCTAssertEqual(object_a.get_relation_object("child", 0), objects.at("sample_b").at(1));
            XCTAssertEqual(objects.at("sample_b").at(1).get_relation_object("parent", 0), object_a);

            XCTAssertEqual(objects.at("sample_c").size(), 1);
            XCTAssertEqual(object_a.get_relation_object("friend", 0), objects.at("sample_c").at(1));
            XCTAssertEqual(objects.at("sample_c").at(1).get_relation_object("friend", 0), object_a);
        });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_fetch_const_objects_by_ids {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) mutable { XCTAssertTrue(result); });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 3}};
        },
        [self, &manager](auto result) mutable {
            XCTAssertTrue(result);
            auto &objects = result.value();

            XCTAssertEqual(manager.current_save_id(), db::value{1});
            XCTAssertEqual(manager.last_save_id(), db::value{1});

            objects.at("sample_a").at(0).set_attribute("name", db::value{"value_1"});
            objects.at("sample_a").at(1).set_attribute("name", db::value{"value_2"});
            objects.at("sample_a").at(2).set_attribute("name", db::value{"value_3"});

            XCTAssertEqual(objects.at("sample_a").at(0).object_id(), db::value{1});
            XCTAssertEqual(objects.at("sample_a").at(1).object_id(), db::value{2});
            XCTAssertEqual(objects.at("sample_a").at(2).object_id(), db::value{3});
        });

    manager.save([self](auto save_result) { XCTAssertTrue(save_result); });

    manager.fetch_const_objects(
        []() {
            return db::integer_set_map{{"sample_a", {2}}};
        },
        [self](auto fetch_result) mutable {
            XCTAssertTrue(fetch_result);

            auto const &objects = fetch_result.value();
            XCTAssertEqual(objects.count("sample_a"), 1);
            auto &a_objects = objects.at("sample_a");
            XCTAssertEqual(a_objects.size(), 1);
            XCTAssertEqual(a_objects.at(2).object_id(), db::value{2});
            XCTAssertEqual(a_objects.at(2).get_attribute("name"), db::value{"value_2"});
        });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_save_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
        XCTAssertEqual(manager.last_save_id(), db::value{0});
    });

    std::unordered_map<db::integer::type, db::object> main_objects;

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, &main_objects, exp1](auto result) {
            db::object_vector_map const &objects = result.value();
            db::object_vector const &a_objects = objects.at("sample_a");
            for (auto const &obj : a_objects) {
                main_objects.insert(std::make_pair(obj.object_id().get<db::integer>(), obj));
            }

            XCTAssertEqual(main_objects.size(), 1);

            auto const &obj = a_objects.at(0);
            XCTAssertEqual(obj.save_id(), db::value{1});
            XCTAssertEqual(obj.get_attribute("name"), db::value{"default_value"});
            XCTAssertEqual(obj.status(), db::object_status::saved);
            XCTAssertEqual(obj.action(), db::value{db::insert_action});

            [exp1 fulfill];
        });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{1});
    XCTAssertEqual(manager.last_save_id(), db::value{1});

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.save([self, exp2](auto save_result) {
        auto const &objects = save_result.value();
        XCTAssertEqual(objects.size(), 0);

        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(main_objects.size(), 1);
    auto &object = main_objects.at(1);
    object.set_attribute("name", db::value{"new_value"});
    object.set_attribute("age", db::value{77});
    object.push_back_relation_id("child", db::value{100});
    object.push_back_relation_id("child", db::value{200});
    XCTAssertEqual(object.status(), db::object_status::changed);

    XCTestExpectation *exp3 = [self expectationWithDescription:@"3"];

    manager.save([self, exp3](auto save_result) {
        XCTAssertTrue(save_result);

        auto const &objects = save_result.value();
        XCTAssertGreaterThan(objects.count("sample_a"), 0);

        auto const &a_objects = objects.at("sample_a");
        XCTAssertEqual(a_objects.size(), 1);

        auto const &obj = a_objects.at(0);
        XCTAssertEqual(obj.save_id(), db::value{2});
        XCTAssertEqual(obj.get_attribute("name"), db::value{"new_value"});
        XCTAssertEqual(obj.get_attribute("age"), db::value{77});
        XCTAssertEqual(obj.status(), db::object_status::saved);
        XCTAssertEqual(obj.action(), db::value{db::update_action});
        XCTAssertEqual(obj.relation_size("child"), 2);
        XCTAssertEqual(obj.get_relation_ids("child").size(), 2);
        XCTAssertEqual(obj.get_relation_id("child", 0), db::value{100});
        XCTAssertEqual(obj.get_relation_id("child", 1), db::value{200});
    });

    manager.execute([self, exp3, &manager](operation const &) {
        auto &db = manager.database();

        auto value_result = db::select(db, db::select_option{.table = "sample_a"});
        auto const &selected_values = value_result.value();

        XCTAssertEqual(selected_values.size(), 2);
        XCTAssertEqual(selected_values.at(0).at("name"), db::value{"default_value"});
        XCTAssertEqual(selected_values.at(0).at("age"), db::value{10});
        XCTAssertEqual(selected_values.at(0).at(db::save_id_field), db::value{1});
        XCTAssertEqual(selected_values.at(0).at(db::action_field), db::value{db::insert_action});
        XCTAssertEqual(selected_values.at(1).at("name"), db::value{"new_value"});
        XCTAssertEqual(selected_values.at(1).at("age"), db::value{77});
        XCTAssertEqual(selected_values.at(1).at(db::save_id_field), db::value{2});
        XCTAssertEqual(selected_values.at(1).at(db::action_field), db::value{db::update_action});

        auto relation_result =
            db::select(db, db::select_option{.table = manager.model().relation("sample_a", "child").table_name});
        auto const &selected_relations = relation_result.value();

        XCTAssertEqual(selected_relations.size(), 2);
        XCTAssertEqual(selected_relations.at(0).at(db::tgt_obj_id_field), db::value{100});
        XCTAssertEqual(selected_relations.at(1).at(db::tgt_obj_id_field), db::value{200});

        [exp3 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{2});
    XCTAssertEqual(manager.last_save_id(), db::value{2});
    XCTAssertEqual(object.get_attribute("name"), db::value{"new_value"});
    XCTAssertEqual(object.get_attribute("age"), db::value{77});
    XCTAssertEqual(object.save_id(), db::value{2});
    XCTAssertEqual(object.status(), db::object_status::saved);
    XCTAssertEqual(object.relation_size("child"), 2);
    XCTAssertEqual(object.get_relation_ids("child").size(), 2);
    XCTAssertEqual(object.get_relation_id("child", 0), db::value{100});
    XCTAssertEqual(object.get_relation_id("child", 1), db::value{200});

    object.remove();

    XCTAssertEqual(object.status(), db::object_status::changed);

    XCTestExpectation *exp4 = [self expectationWithDescription:@"4"];

    manager.save([self, exp4](auto save_result) {
        XCTAssertTrue(save_result);

        auto const &objects = save_result.value();
        XCTAssertGreaterThan(objects.count("sample_a"), 0);

        auto const &a_objects = objects.at("sample_a");
        XCTAssertEqual(a_objects.size(), 1);

        auto const &obj = a_objects.at(0);
        XCTAssertEqual(obj.save_id(), db::value{3});
        XCTAssertEqual(obj.get_attribute("name"), db::value::null_value());
        XCTAssertEqual(obj.get_attribute("age"), db::value{10});
        XCTAssertEqual(obj.relation_size("child"), 0);
        XCTAssertEqual(obj.get_relation_ids("child").size(), 0);
        XCTAssertTrue(obj.is_removed());
        XCTAssertEqual(obj.status(), db::object_status::saved);
        XCTAssertEqual(obj.action(), db::value{db::remove_action});

        [exp4 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{3});
    XCTAssertEqual(manager.last_save_id(), db::value{3});

    manager.save([self](auto save_result) {
        XCTAssertTrue(save_result);

        auto const &objects = save_result.value();
        XCTAssertEqual(objects.size(), 0);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{3});
    XCTAssertEqual(manager.last_save_id(), db::value{3});
}

- (void)test_save_with_delete {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
        XCTAssertEqual(manager.last_save_id(), db::value{0});
    });

    db::object_vector a_objects;

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 2}};
        },
        [self, &manager, &a_objects](auto result) {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{1});

            auto &objects = result.value();
            XCTAssertEqual(objects.count("sample_a"), 1);

            a_objects = std::move(objects.at("sample_a"));
            XCTAssertEqual(a_objects.size(), 2);

            auto &object = a_objects.at(0);
            object.set_attribute("name", db::value{"name_value_0"});
        });

    manager.save([self, &manager, &a_objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{2});
        XCTAssertEqual(a_objects.at(0).save_id(), db::value{2});

        auto &object = a_objects.at(1);
        object.set_attribute("name", db::value{"name_value_1_a"});
    });

    manager.save([self, &manager, &a_objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{3});
        XCTAssertEqual(a_objects.at(1).save_id(), db::value{3});
    });

    manager.revert([]() { return 2; },
                   [self, &manager, &a_objects](auto result) {
                       XCTAssertTrue(result);
                       XCTAssertEqual(manager.current_save_id(), db::value{2});

                       auto &object = a_objects.at(1);
                       object.set_attribute("name", db::value{"name_value_1_b"});
                   });

    manager.save([self, &manager, &a_objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{3});
        XCTAssertEqual(a_objects.at(1).save_id(), db::value{3});
    });

    manager.execute([self, &manager](operation const &op) {
        auto &db = manager.database();
        auto result = db::select(db, {.table = "sample_a"});

        auto &object_datas = result.value();
        XCTAssertEqual(object_datas.size(), 4);

        for (auto &object_data : object_datas) {
            XCTAssertNotEqual(object_data.at("name"), db::value{"name_value_1_a"});
        }
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_revert_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    db::object a_object{nullptr};

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
        XCTAssertEqual(manager.last_save_id(), db::value{0});
    });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, &a_object](auto result) mutable {
            a_object = result.value().at("sample_a").at(0);

            XCTAssertEqual(a_object.save_id(), db::value{1});

            a_object.set_attribute("name", db::value{"value_2"});
        });

    manager.save([self, &a_object](auto result) mutable {
        XCTAssertTrue(result);

        XCTAssertEqual(a_object.save_id(), db::value{2});

        a_object.remove();
    });

    manager.save([self, &a_object](auto result) mutable {
        XCTAssertTrue(result);

        XCTAssertEqual(a_object.save_id(), db::value{3});
        XCTAssertTrue(a_object.is_removed());
    });

    manager.revert([]() { return 2; },
                   [self, &a_object](auto result) mutable {
                       XCTAssertTrue(result);

                       XCTAssertEqual(a_object.save_id(), db::value{2});
                       XCTAssertEqual(a_object.get_attribute("name"), db::value{"value_2"});
                       XCTAssertFalse(a_object.is_removed());
                   });

    manager.revert([]() { return 1; },
                   [self, &a_object](auto result) mutable {
                       XCTAssertTrue(result);

                       XCTAssertEqual(a_object.save_id(), db::value{1});
                       XCTAssertEqual(a_object.get_attribute("name"), db::value{"default_value"});

                       a_object.set_attribute("name", db::value{"value_b"});
                   });

    manager.save([self](auto result) mutable { XCTAssertTrue(result); });

    manager.execute([self, &manager](operation const &) mutable {
        auto &db = manager.database();

        auto select_result = db::select(
            db, db::select_option{.table = "sample_a", .where_exprs = db::expr(db::save_id_field, "=", "3")});
        XCTAssertTrue(select_result);
        XCTAssertEqual(select_result.value().size(), 0);

        select_result = db::select(
            db, db::select_option{.table = "sample_a", .where_exprs = db::expr(db::save_id_field, "=", "2")});
        XCTAssertTrue(select_result);
        XCTAssertEqual(select_result.value().size(), 1);

        select_result = db::select(
            db, db::select_option{.table = "sample_a", .where_exprs = db::expr(db::save_id_field, "=", "1")});
        XCTAssertTrue(select_result);
        XCTAssertEqual(select_result.value().size(), 1);
    });

    manager.revert([]() { return 0; },
                   [self, &a_object](auto result) mutable {
                       XCTAssertTrue(result);

                       XCTAssertEqual(a_object.status(), db::object_status::invalid);
                       XCTAssertFalse(a_object.save_id());
                       XCTAssertFalse(a_object.action());
                       XCTAssertFalse(a_object.get_attribute("name"));

                   });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_restore_reverted_db {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    if (auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)]) {
        db::object_vector_map objects;

        manager.setup([self, &manager](auto result) mutable {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{0});
            XCTAssertEqual(manager.last_save_id(), db::value{0});
        });

        manager.insert_objects(
            []() {
                return db::entity_count_map{{"sample_a", 1}, {"sample_b", 2}};
            },
            [self, &manager, &objects](auto result) mutable {
                XCTAssertTrue(result);
                XCTAssertEqual(manager.current_save_id(), db::value{1});
                XCTAssertEqual(manager.last_save_id(), db::value{1});

                objects = std::move(result.value());

                objects.at("sample_a").at(0).set_attribute("name", db::value{"name_value_1"});
                objects.at("sample_b").at(0).set_attribute("name", db::value{"name_value_2"});
                objects.at("sample_b").at(1).set_attribute("name", db::value{"name_value_3"});
            });

        manager.save([self, &manager, &objects](auto result) mutable {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{2});
            XCTAssertEqual(manager.last_save_id(), db::value{2});

            objects.at("sample_a").at(0).set_attribute("name", db::value{"name_value_4"});
            objects.at("sample_b").at(0).set_attribute("name", db::value{"name_value_5"});
            objects.at("sample_a").at(0).set_relation_object("child", {objects.at("sample_b").at(0)});
            XCTAssertEqual(objects.at("sample_b").at(0).object_id(), db::value{1});
        });

        manager.save([self, &manager, &objects](auto result) mutable {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{3});
            XCTAssertEqual(manager.last_save_id(), db::value{3});

            objects.at("sample_a").at(0).set_attribute("name", db::value{"name_value_6"});
            objects.at("sample_b").at(1).set_attribute("name", db::value{"name_value_7"});
            objects.at("sample_a").at(0).set_relation_object("child", {objects.at("sample_b").at(1)});
        });

        manager.save([self, &manager](auto result) mutable {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{4});
            XCTAssertEqual(manager.last_save_id(), db::value{4});
        });

        manager.revert([]() { return 3; },
                       [self, &manager](auto result) mutable {
                           XCTAssertTrue(result);
                           XCTAssertEqual(manager.current_save_id(), db::value{3});
                           XCTAssertEqual(manager.last_save_id(), db::value{4});
                       });

        XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
        manager.execute([exp](auto const &op) { [exp fulfill]; });
        [self waitForExpectationsWithTimeout:1.0 handler:nil];
    } else {
        XCTAssert(0);
    }

    if (auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)]) {
        db::object_vector_map objects{};

        manager.setup([self, &manager](auto result) mutable {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{3});
            XCTAssertEqual(manager.last_save_id(), db::value{4});
        });

        manager.fetch_objects([]() { return db::select_option{.table = "sample_a"}; },
                              [self, &objects](auto result) mutable {
                                  XCTAssertTrue(result);

                                  objects = std::move(result.value());

                                  XCTAssertEqual(objects.count("sample_a"), 1);
                                  XCTAssertEqual(objects.at("sample_a").at(0).get_attribute("name"),
                                                 db::value{"name_value_4"});
                                  XCTAssertEqual(objects.at("sample_a").at(0).relation_size("child"), 1);
                              });

        manager.fetch_objects(
            [&objects]() { return db::relation_ids(objects); },
            [self, &objects](auto result) mutable {
                XCTAssertTrue(result);

                db::object_map_map &rel_objects = result.value();

                XCTAssertEqual(rel_objects.count("sample_b"), 1);
                XCTAssertEqual(rel_objects.at("sample_b").at(1).get_attribute("name"), db::value{"name_value_5"});

                auto sample_bs =
                    to_vector<db::object>(rel_objects.at("sample_b"), [](auto &pair) { return pair.second; });
                objects.emplace(std::make_pair("sample_b", std::move(sample_bs)));

                XCTAssertEqual(objects.at("sample_a").at(0).get_relation_object("child", 0).get_attribute("name"),
                               db::value{"name_value_5"});
            });

        XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
        manager.execute([exp](auto const &op) { [exp fulfill]; });
        [self waitForExpectationsWithTimeout:1.0 handler:nil];
    } else {
        XCTAssert(0);
    }
}

- (void)test_suspend_and_priority {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1) priority_count:2];

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];
    manager.setup([exp1](auto) { [exp1 fulfill]; });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.suspend();

    int call_count = 0;
    int fetched_object_count = 0;

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [&call_count, exp2](auto) {
            call_count++;
            if (call_count == 2) {
                [exp2 fulfill];
            }
        },
        {.priority = 1});

    manager.fetch_objects([]() { return db::select_option{.table = "sample_a"}; },
                          [&call_count, exp2, &fetched_object_count, self](auto result) {
                              XCTAssertTrue(result);
                              XCTAssertEqual(result.value().count("sample_a"), 0);

                              call_count++;
                              if (call_count == 2) {
                                  [exp2 fulfill];
                              }
                          },
                          {.priority = 0});

    manager.resume();

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_clear {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    db::object object{nullptr};

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, &object](auto result) {
            XCTAssertTrue(result);
            auto &objects = result.value();
            auto &a_objects = objects.at("sample_a");

            object = std::move(a_objects.at(0));

            object.set_attribute("name", db::value{"test_clear_value"});
        });

    manager.save([self, &manager, &object](auto result) {
        XCTAssertTrue(result);

        XCTAssertEqual(object.status(), db::object_status::saved);
        XCTAssertEqual(object.object_id(), db::value{1});
        XCTAssertEqual(object.get_attribute("name"), db::value{"test_clear_value"});

        XCTAssertTrue(manager.cached_object("sample_a", 1));
    });

    manager.clear([self, &manager, &object](auto result) {
        XCTAssertTrue(result);

        XCTAssertEqual(object.status(), db::object_status::invalid);
        XCTAssertFalse(object.get_attribute("name"));

        XCTAssertFalse(manager.cached_object("sample_a", 1));
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_purge {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    db::object_vector_map objects;

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}, {"sample_b", 2}};
        },
        [self, &manager, &objects](auto result) {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{1});

            objects = result.value();
            auto &obj_a = objects.at("sample_a").at(0);
            auto &obj_b0 = objects.at("sample_b").at(0);
            auto &obj_b1 = objects.at("sample_b").at(1);

            obj_a.set_attribute("name", db::value{"obj_a_2"});
            obj_b0.set_attribute("name", db::value{"obj_b0_2"});
            obj_b1.set_attribute("name", db::value{"obj_b1_2"});

            obj_a.set_relation_object("child", {obj_b0});
        });

    manager.save([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{2});

        auto &obj_a = objects.at("sample_a").at(0);
        auto &obj_b0 = objects.at("sample_b").at(0);
        auto &obj_b1 = objects.at("sample_b").at(1);

        obj_a.set_attribute("name", db::value{"obj_a_3"});
        obj_b0.set_attribute("name", db::value{"obj_b0_3"});
        obj_b1.set_attribute("name", db::value{"obj_b1_3"});

        obj_a.set_relation_object("child", {obj_b0, obj_b1});
    });

    manager.save([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{3});

        auto &obj_a = objects.at("sample_a").at(0);
        auto &obj_b0 = objects.at("sample_b").at(0);
        auto &obj_b1 = objects.at("sample_b").at(1);

        obj_a.set_attribute("name", db::value{"obj_a_4"});
        obj_b0.set_attribute("name", db::value{"obj_b0_4"});
        obj_b1.set_attribute("name", db::value{"obj_b1_4"});

        obj_a.set_relation_object("child", {obj_b1});
    });

    manager.save([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{4});
    });

    manager.revert([]() { return 3; },
                   [self, &manager](auto result) {
                       XCTAssertTrue(result);
                       XCTAssertEqual(manager.current_save_id(), db::value{3});
                       XCTAssertEqual(manager.last_save_id(), db::value{4});
                   });

    manager.purge([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{1});
        XCTAssertEqual(manager.last_save_id(), db::value{1});

        auto &obj_a = objects.at("sample_a").at(0);
        auto &obj_b0 = objects.at("sample_b").at(0);
        auto &obj_b1 = objects.at("sample_b").at(1);

        XCTAssertEqual(obj_a.get_attribute("name"), db::value{"obj_a_3"});
        XCTAssertEqual(obj_b0.get_attribute("name"), db::value{"obj_b0_3"});
        XCTAssertEqual(obj_b1.get_attribute("name"), db::value{"obj_b1_3"});

        XCTAssertEqual(obj_a.save_id(), db::value{1});
        XCTAssertEqual(obj_b0.save_id(), db::value{1});
        XCTAssertEqual(obj_b1.save_id(), db::value{1});

    });

    manager.execute([self, &manager](auto const &op) {
        auto &db = manager.database();
        auto const &rel_table_name = manager.model().entities().at("sample_a").relations.at("child").table_name;

        auto select_a_result = db::select(db, db::select_option{.table = "sample_a"});
        XCTAssertTrue(select_a_result);

        auto &a_objects = select_a_result.value();
        XCTAssertEqual(a_objects.size(), 1);

        XCTAssertEqual(a_objects.at(0).at("name"), db::value{"obj_a_3"});
        XCTAssertEqual(a_objects.at(0).at(db::save_id_field), db::value{1});

        auto select_b_result = db::select(db, db::select_option{.table = "sample_b"});
        XCTAssertTrue(select_b_result);

        auto &b_objects = select_b_result.value();
        XCTAssertEqual(b_objects.size(), 2);

        auto b_object_map = to_map<db::integer::type>(
            b_objects, [](db::value_map &obj) { return obj.at(db::object_id_field).get<db::integer>(); });

        XCTAssertEqual(b_object_map.at(1).at("name"), db::value{"obj_b0_3"});
        XCTAssertEqual(b_object_map.at(1).at(db::save_id_field), db::value{1});
        XCTAssertEqual(b_object_map.at(2).at("name"), db::value{"obj_b1_3"});
        XCTAssertEqual(b_object_map.at(2).at(db::save_id_field), db::value{1});

        auto select_rel_result = db::select(db, db::select_option{.table = rel_table_name});
        XCTAssertTrue(select_rel_result);

        auto &rel_objects = select_rel_result.value();
        XCTAssertEqual(rel_objects.size(), 2);

        XCTAssertEqual(rel_objects.at(0).at(db::src_id_field), db::value{3});
        XCTAssertEqual(rel_objects.at(0).at(db::src_obj_id_field), db::value{1});
        XCTAssertEqual(rel_objects.at(0).at(db::tgt_obj_id_field), db::value{1});
        XCTAssertEqual(rel_objects.at(0).at(db::save_id_field), db::value{1});
        XCTAssertEqual(rel_objects.at(1).at(db::src_id_field), db::value{3});
        XCTAssertEqual(rel_objects.at(1).at(db::src_obj_id_field), db::value{1});
        XCTAssertEqual(rel_objects.at(1).at(db::tgt_obj_id_field), db::value{2});
        XCTAssertEqual(rel_objects.at(1).at(db::save_id_field), db::value{1});
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_has_inserted {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);

        XCTAssertFalse(manager.has_inserted_objects());

        manager.insert_object("sample_a");

        XCTAssertTrue(manager.has_inserted_objects());
    });

    manager.save([self, &manager](auto result) {
        XCTAssertTrue(result);

        XCTAssertFalse(manager.has_inserted_objects());
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_has_changed {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, &manager](auto result) {
            XCTAssertFalse(manager.has_changed_objects());

            auto &obj = result.value().at("sample_a").at(0);
            obj.set_attribute("name", db::value{"a"});

            XCTAssertTrue(manager.has_changed_objects());
        });

    manager.save([self, &manager](auto result) { XCTAssertFalse(manager.has_changed_objects()); });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_inserted_object_count {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);

        XCTAssertEqual(manager.inserted_object_count("sample_a"), 0);

        manager.insert_object("sample_a");

        XCTAssertEqual(manager.inserted_object_count("sample_a"), 1);

        manager.insert_object("sample_a");

        XCTAssertEqual(manager.inserted_object_count("sample_a"), 2);
    });

    manager.save([self, &manager](auto result) {
        XCTAssertTrue(result);

        XCTAssertEqual(manager.inserted_object_count("sample_a"), 0);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_changed_object_count {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 2}};
        },
        [self, &manager](auto result) {
            XCTAssertEqual(manager.changed_object_count("sample_a"), 0);

            auto &obj = result.value().at("sample_a").at(0);
            obj.set_attribute("name", db::value{"a"});

            XCTAssertEqual(manager.changed_object_count("sample_a"), 1);

            obj = result.value().at("sample_a").at(1);
            obj.set_attribute("name", db::value{"b"});

            XCTAssertEqual(manager.changed_object_count("sample_a"), 2);
        });

    manager.save([self, &manager](auto result) {
        XCTAssertTrue(result);

        XCTAssertEqual(manager.changed_object_count("sample_a"), 0);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_reset {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    db::object_vector_map objects;

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}, {"sample_b", 2}};
        },
        [self, &manager, &objects](auto result) {
            XCTAssertTrue(result);

            objects = std::move(result.value());
            auto &obj_a = objects.at("sample_a").at(0);
            auto &obj_b0 = objects.at("sample_b").at(0);
            auto &obj_b1 = objects.at("sample_b").at(1);

            obj_a.set_attribute("name", db::value{"a_test_1"});
            obj_b0.set_attribute("name", db::value{"b0_test_1"});
            obj_b1.set_attribute("name", db::value{"b1_test_1"});
            obj_a.set_relation_object("child", {obj_b0});
        });

    manager.save([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        auto &obj_a = objects.at("sample_a").at(0);
        auto &obj_b0 = objects.at("sample_b").at(0);
        auto &obj_b1 = objects.at("sample_b").at(1);

        obj_a.set_attribute("name", db::value{"a_test_2"});
        obj_b0.set_attribute("name", db::value{"b0_test_2"});
        obj_b1.set_attribute("name", db::value{"b1_test_2"});
        obj_a.set_relation_object("child", {obj_b1, obj_b0});

        XCTAssertEqual(obj_a.status(), db::object_status::changed);
        XCTAssertEqual(obj_b0.status(), db::object_status::changed);
        XCTAssertEqual(obj_b1.status(), db::object_status::changed);

        XCTAssertTrue(manager.has_changed_objects());
    });

    manager.reset([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertFalse(manager.has_changed_objects());

        auto &obj_a = objects.at("sample_a").at(0);
        auto &obj_b0 = objects.at("sample_b").at(0);
        auto &obj_b1 = objects.at("sample_b").at(1);

        XCTAssertEqual(obj_a.get_attribute("name"), db::value{"a_test_1"});
        XCTAssertEqual(obj_b0.get_attribute("name"), db::value{"b0_test_1"});
        XCTAssertEqual(obj_b1.get_attribute("name"), db::value{"b1_test_1"});
        XCTAssertEqual(obj_a.relation_size("child"), 1);
        XCTAssertEqual(obj_a.get_relation_object("child", 0), obj_b0);

        XCTAssertEqual(obj_a.status(), db::object_status::saved);
        XCTAssertEqual(obj_b0.status(), db::object_status::saved);
        XCTAssertEqual(obj_b1.status(), db::object_status::saved);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_observing_object_changed {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, &manager](auto result) {
            XCTAssertTrue(result);

            bool observer_called = false;

            auto observer = manager.subject().make_observer(
                db::manager::object_change_key,
                [&observer_called](std::string const &key, auto const &) { observer_called = true; });

            auto &object = result.value().at("sample_a").at(0);
            object.set_attribute("name", db::value{"test_name"});

            XCTAssertTrue(observer_called);
        });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_observing_db_info_changed {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    std::size_t observing_count = 0;

    auto observer = manager.subject().make_observer(
        db::manager::db_info_change_key,
        [&observing_count](std::string const &key, auto const &) { ++observing_count; });

    manager.setup([self, &manager, &observing_count](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(observing_count, 1);
    });

    manager.insert_objects(
        []() {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, &manager, &observing_count](auto result) {
            XCTAssertEqual(observing_count, 2);

            auto &object = result.value().at("sample_a").at(0);
            object.set_attribute("name", db::value{"test_name"});
        });

    manager.save([self, &observing_count](auto result) { XCTAssertEqual(observing_count, 3); });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_dispatch_queue {
    dispatch_queue_t queue = dispatch_queue_create("test", DISPATCH_QUEUE_SERIAL);

    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1) priority_count:1 dispatch_queue:queue];

    XCTAssertEqualObjects(manager.dispatch_queue(), queue);

    manager.setup([self](auto result) { XCTAssertFalse([NSThread isMainThread]); });

    manager.insert_objects(
        [self]() {
            XCTAssertFalse([NSThread isMainThread]);
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self](auto result) {
            XCTAssertFalse([NSThread isMainThread]);
            auto &object = result.value().at("sample_a").at(0);
            object.set_attribute("name", db::value{"x"});
        });

    manager.save([self](auto result) { XCTAssertFalse([NSThread isMainThread]); });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute([exp](auto const &op) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_make_error {
    auto error = db::manager::error{db::manager::error_type::version_not_found};
    XCTAssertTrue(error);
    XCTAssertEqual(error.type(), db::manager::error_type::version_not_found);
}

- (void)test_error_none {
    db::manager::error error{nullptr};
    XCTAssertFalse(error);
    XCTAssertEqual(error.type(), db::manager::error_type::none);
}

- (void)test_to_string_from_error {
    XCTAssertEqual(to_string(db::manager::error_type::begin_transaction_failed), "begin_transaction_failed");
    XCTAssertEqual(to_string(db::manager::error_type::vacuum_failed), "vacuum_failed");
    XCTAssertEqual(to_string(db::manager::error_type::select_info_failed), "select_info_failed");
    XCTAssertEqual(to_string(db::manager::error_type::update_info_failed), "update_info_failed");
    XCTAssertEqual(to_string(db::manager::error_type::version_not_found), "version_not_found");
    XCTAssertEqual(to_string(db::manager::error_type::invalid_version_text), "invalid_version_text");
    XCTAssertEqual(to_string(db::manager::error_type::alter_entity_table_failed), "alter_entity_table_failed");
    XCTAssertEqual(to_string(db::manager::error_type::create_info_table_failed), "create_info_table_failed");
    XCTAssertEqual(to_string(db::manager::error_type::insert_info_failed), "insert_info_failed");
    XCTAssertEqual(to_string(db::manager::error_type::create_entity_table_failed), "create_entity_table_failed");
    XCTAssertEqual(to_string(db::manager::error_type::create_relation_table_failed), "create_relation_table_failed");
    XCTAssertEqual(to_string(db::manager::error_type::create_index_failed), "create_index_failed");
    XCTAssertEqual(to_string(db::manager::error_type::insert_attributes_failed), "insert_attributes_failed");
    XCTAssertEqual(to_string(db::manager::error_type::insert_relation_failed), "insert_relation_failed");
    XCTAssertEqual(to_string(db::manager::error_type::save_id_not_found), "save_id_not_found");
    XCTAssertEqual(to_string(db::manager::error_type::update_save_id_failed), "update_save_id_failed");
    XCTAssertEqual(to_string(db::manager::error_type::delete_failed), "delete_failed");
    XCTAssertEqual(to_string(db::manager::error_type::purge_failed), "purge_failed");
    XCTAssertEqual(to_string(db::manager::error_type::purge_relation_failed), "purge_relation_failed");
    XCTAssertEqual(to_string(db::manager::error_type::select_last_failed), "select_last_failed");
    XCTAssertEqual(to_string(db::manager::error_type::select_revert_failed), "select_revert_failed");
    XCTAssertEqual(to_string(db::manager::error_type::fetch_object_datas_failed), "fetch_object_datas_failed");
    XCTAssertEqual(to_string(db::manager::error_type::out_of_range_save_id), "out_of_range_save_id");
    XCTAssertEqual(to_string(db::manager::error_type::select_failed), "select_failed");
    XCTAssertEqual(to_string(db::manager::error_type::last_insert_rowid_failed), "last_insert_rowid_failed");
    XCTAssertEqual(to_string(db::manager::error_type::none), "none");
}

@end
