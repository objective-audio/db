//
//  yas_db_manager_tests.mm
//

#import "yas_db_test_utils.h"

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

    XCTestExpectation *expectation = [self expectationWithDescription:@"execution"];

    manager.execute([self, expectation](auto &database, auto const &operation) {
        XCTAssertTrue(database);
        XCTAssertTrue(operation);
        XCTAssertFalse([NSThread isMainThread]);
        [expectation fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_execute_update_and_query_in_bg {
    auto manager = [yas_db_test_utils create_test_manager];

    XCTestExpectation *expectation = [self expectationWithDescription:@"execution"];

    manager.execute([self, expectation](db::database &db, auto const &operation) {
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

        [expectation fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_setup {
    db::model model{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model)];

    XCTestExpectation *expectation = [self expectationWithDescription:@"setup"];

    manager.setup([self](auto const &result) { XCTAssertTrue(result); });

    manager.execute([self, expectation](db::database &db, auto const &op) {
        XCTAssertTrue(db::table_exists(db, db::info_table));
        auto select_infos_result = db::select(db, db::info_table);
        XCTAssertTrue(select_infos_result);
        XCTAssertEqual(select_infos_result.value().size(), 1);
        XCTAssertEqual(select_infos_result.value().at(0).at(db::version_field).get<db::text>(), "0.0.1");

        XCTAssertTrue(db::table_exists(db, "sample_a"));
        auto select_result_a = db::select(db, "sample_a");
        XCTAssertTrue(select_result_a);
        XCTAssertEqual(select_result_a.value().size(), 0);

        XCTAssertTrue(db::table_exists(db, "rel_sample_a_child"));
        auto select_rels_result = db::select(db, "rel_sample_a_child");
        XCTAssertTrue(select_rels_result);
        XCTAssertEqual(select_rels_result.value().size(), 0);

        [expectation fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_setup_migration {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *first_expectation = [self expectationWithDescription:@"setup_1"];

    manager.setup([self](auto const &result) { XCTAssertTrue(result); });

    manager.execute([self, first_expectation](db::database &db, auto const &) {
        db::begin_transaction(db);

        bool rollback = false;

        if (!db.execute_update(db::insert_sql("sample_a", {"age", "name", "weight"}),
                               {db::value{2}, db::value{"xyz"}, db::value{451.2}})) {
            rollback = true;
        }

        if (!db.execute_update(db::insert_sql("sample_b", {"name"}), {db::value{"qwerty"}})) {
            rollback = true;
        }

        db::select_option option{.fields = {db::id_field}};

        auto select_result_a = db::select(db, "sample_a", option);
        auto &src_id = select_result_a.value().at(0).at(db::id_field);

        auto select_result_b = db::select(db, "sample_b", option);
        auto &tgt_id = select_result_b.value().at(0).at(db::id_field);

        auto sql = db::insert_sql("rel_sample_a_child", {db::src_id_field, db::tgt_id_field});
        if (!db.execute_update(sql, db::value_vector{src_id, tgt_id})) {
            rollback = true;
        }

        if (!db.execute_update(db::update_sql(db::info_table, {db::save_id_field}, ""), {db::value{100}})) {
            rollback = true;
        }

        XCTAssertFalse(rollback);

        if (rollback) {
            db::rollback(db);
        } else {
            db::commit(db);
        }

        [first_expectation fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    manager = nullptr;

    XCTestExpectation *second_expectation = [self expectationWithDescription:@"setup_2"];

    db::model model_0_0_2{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_2]};
    manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self](auto const &result) { XCTAssertTrue(result); });

    manager.execute([self, second_expectation](db::database &db, auto const &) {
        XCTAssertTrue(db::table_exists(db, db::info_table));
        auto select_infos_result = db::select(db, db::info_table);
        XCTAssertTrue(select_infos_result);
        XCTAssertEqual(select_infos_result.value().size(), 1);
        XCTAssertEqual(select_infos_result.value().at(0).at(db::version_field).get<db::text>(), "0.0.2");
        XCTAssertEqual(select_infos_result.value().at(0).at(db::save_id_field).get<db::integer>(), 100);

        XCTAssertTrue(db::table_exists(db, "sample_a"));
        auto select_result_a = db::select(db, "sample_a");
        XCTAssertTrue(select_result_a);
        XCTAssertEqual(select_result_a.value().size(), 1);

        auto const &sample_a = select_result_a.value().at(0);
        XCTAssertEqual(sample_a.at("age").get<db::integer>(), 2);
        XCTAssertEqual(sample_a.at("name").get<db::text>(), "xyz");
        XCTAssertEqual(sample_a.at("weight").get<db::real>(), 451.2);

        XCTAssertTrue(db::table_exists(db, "sample_b"));
        auto select_result_b = db::select(db, "sample_b");
        XCTAssertTrue(select_result_b);
        XCTAssertEqual(select_result_b.value().size(), 1);

        auto const &sample_b = select_result_b.value().at(0);
        XCTAssertEqual(sample_b.at("name").get<db::text>(), "qwerty");

        XCTAssertTrue(db::table_exists(db, "sample_c"));
        auto select_result_c = db::select(db, "sample_c");
        XCTAssertTrue(select_result_c);
        XCTAssertEqual(select_result_c.value().size(), 0);

        XCTAssertTrue(db::table_exists(db, "rel_sample_a_child"));
        auto select_rels_result = db::select(db, "rel_sample_a_child");
        XCTAssertEqual(select_rels_result.value().size(), 1);

        auto &src_id = sample_a.at(db::id_field);
        auto &tgt_id = sample_b.at(db::id_field);

        auto &rel = select_rels_result.value().at(0);
        XCTAssertEqual(rel.at(db::src_id_field), src_id);
        XCTAssertEqual(rel.at(db::tgt_id_field), tgt_id);

        [second_expectation fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_insert_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *expectation_1 = [self expectationWithDescription:@"insert_1"];

    manager.setup([self, &manager](auto const &result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.save_id(), 0);
    });

    db::object_map_map inserted_objects_1;

    manager.insert_objects({{"sample_a", 3}},
                           [self, expectation_1, &inserted_objects_1, &manager](auto const &insert_result) {
                               XCTAssertTrue(insert_result);

                               inserted_objects_1 = std::move(insert_result.value());
                               XCTAssertGreaterThan(inserted_objects_1.count("sample_a"), 0);

                               db::object_map const &objects = inserted_objects_1.at("sample_a");
                               XCTAssertEqual(objects.size(), 3);

                               XCTAssertGreaterThan(objects.count(1), 0);
                               XCTAssertGreaterThan(objects.count(2), 0);
                               XCTAssertGreaterThan(objects.count(3), 0);

                               XCTAssertEqual(objects.at(1).object_id(), db::value{1});
                               XCTAssertEqual(objects.at(2).object_id(), db::value{2});
                               XCTAssertEqual(objects.at(3).object_id(), db::value{3});

                               XCTAssertEqual(objects.at(1).save_id(), db::value{1});
                               XCTAssertEqual(objects.at(2).save_id(), db::value{1});
                               XCTAssertEqual(objects.at(3).save_id(), db::value{1});

                               XCTAssertEqual(objects.at(1).manager(), manager);
                               XCTAssertEqual(objects.at(2).manager(), manager);
                               XCTAssertEqual(objects.at(3).manager(), manager);

                               [expectation_1 fulfill];
                           });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(inserted_objects_1.size(), 1);
    XCTAssertGreaterThan(inserted_objects_1.count("sample_a"), 0);
    XCTAssertGreaterThan(inserted_objects_1.at("sample_a").count(1), 0);
    XCTAssertGreaterThan(inserted_objects_1.at("sample_a").count(2), 0);
    XCTAssertGreaterThan(inserted_objects_1.at("sample_a").count(3), 0);

    XCTAssertEqual(manager.save_id(), 1);

    XCTestExpectation *expectation_2 = [self expectationWithDescription:@"insert_2"];

    db::object_map_map inserted_objects_2;

    manager.insert_objects({{"sample_a", 1}},
                           [self, expectation_2, &inserted_objects_2, &manager](auto const &insert_result) {
                               XCTAssertTrue(insert_result);

                               inserted_objects_2 = std::move(insert_result.value());
                               db::object_map const &objects = inserted_objects_2.at("sample_a");

                               XCTAssertEqual(objects.size(), 1);

                               XCTAssertEqual(objects.at(4).object_id(), db::value{4});
                               XCTAssertEqual(objects.at(4).save_id(), db::value{2});
                               XCTAssertEqual(objects.at(4).manager(), manager);

                               [expectation_2 fulfill];
                           });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(inserted_objects_2.size(), 1);
    XCTAssertEqual(inserted_objects_2.count("sample_a"), 1);
    XCTAssertGreaterThan(inserted_objects_2.at("sample_a").count(4), 0);

    XCTAssertEqual(manager.save_id(), 2);

    auto const object_1 = manager.cached_object("sample_a", 1);
    XCTAssertTrue(object_1);
    XCTAssertEqual(object_1.object_id(), db::value{1});

    XCTAssertFalse(manager.cached_object("sample_a", 5));
}

- (void)test_insert_many_entity_objects {
    db::model model_0_0_2{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_2]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self](auto const &result) { XCTAssertTrue(result); });

    XCTestExpectation *expectation_1 = [self expectationWithDescription:@"insert_1"];

    manager.insert_objects({{"sample_a", 3}, {"sample_b", 5}},
                           [self, expectation_1](auto const &insert_result) {
                               db::object_map_map const &entity_objects = insert_result.value();
                               XCTAssertEqual(entity_objects.size(), 2);

                               XCTAssertGreaterThan(entity_objects.count("sample_a"), 0);

                               db::object_map const &objects_a = entity_objects.at("sample_a");
                               XCTAssertEqual(objects_a.size(), 3);

                               XCTAssertGreaterThan(entity_objects.count("sample_b"), 0);

                               db::object_map const &objects_b = entity_objects.at("sample_b");
                               XCTAssertEqual(objects_b.size(), 5);

                               [expectation_1 fulfill];
                           });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_save_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto const &result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.save_id(), 0);
    });

    std::unordered_map<db::integer::type, db::object> main_objects;

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];

    manager.insert_objects({{"sample_a", 1}},
                           [self, &main_objects, exp1](db::manager::insert_result const &insert_result) {
                               db::object_map_map const &entity_objects = insert_result.value();
                               db::object_map const &objects = entity_objects.at("sample_a");
                               for (auto const &obj_pair : objects) {
                                   main_objects.insert(obj_pair);
                               }

                               XCTAssertEqual(main_objects.size(), 1);

                               auto const &obj_pair = *objects.begin();
                               auto const &obj = obj_pair.second;
                               XCTAssertEqual(obj.save_id(), db::value{1});
                               XCTAssertEqual(obj.get("name"), db::value{"default_value"});
                               XCTAssertEqual(obj.status(), db::object_status::saved);

                               [exp1 fulfill];
                           });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.save_id(), 1);

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.save([self, exp2](db::manager::save_result const &save_result) {
        auto const &entity_objects = save_result.value();
        XCTAssertEqual(entity_objects.size(), 0);

        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(main_objects.size(), 1);
    auto &object = main_objects.at(1);
    object.set("name", db::value{"new_value"});
    object.set("age", db::value{77});
    XCTAssertEqual(object.status(), db::object_status::changed);

    XCTestExpectation *exp3 = [self expectationWithDescription:@"3"];

    manager.save([self, exp3](db::manager::save_result const &save_result) {
        XCTAssertTrue(save_result);

        auto const &entity_objects = save_result.value();
        XCTAssertGreaterThan(entity_objects.count("sample_a"), 0);

        auto const &objects = entity_objects.at("sample_a");
        XCTAssertEqual(objects.size(), 1);

        auto const &obj = objects.begin()->second;
        XCTAssertEqual(obj.save_id(), db::value{2});
        XCTAssertEqual(obj.get("name"), db::value{"new_value"});
        XCTAssertEqual(obj.get("age"), db::value{77});
        XCTAssertEqual(obj.status(), db::object_status::saved);
    });

    manager.execute([self, exp3](db::database &db, operation const &) {
        auto select_result = db::select(db, "sample_a");
        auto const &selected_maps = select_result.value();

        XCTAssertEqual(selected_maps.size(), 2);
        XCTAssertEqual(selected_maps.at(0).at("name"), db::value{"default_value"});
        XCTAssertEqual(selected_maps.at(0).at("age"), db::value{10});
        XCTAssertEqual(selected_maps.at(0).at(db::save_id_field), db::value{1});
        XCTAssertEqual(selected_maps.at(1).at("name"), db::value{"new_value"});
        XCTAssertEqual(selected_maps.at(1).at("age"), db::value{77});
        XCTAssertEqual(selected_maps.at(1).at(db::save_id_field), db::value{2});

        [exp3 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.save_id(), 2);
    XCTAssertEqual(object.get("name"), db::value{"new_value"});
    XCTAssertEqual(object.get("age"), db::value{77});
    XCTAssertEqual(object.save_id(), db::value{2});
    XCTAssertEqual(object.status(), db::object_status::saved);

    object.remove();

    XCTAssertEqual(object.status(), db::object_status::changed);

    XCTestExpectation *exp4 = [self expectationWithDescription:@"4"];

    manager.save([self, exp4](db::manager::save_result const &save_result) {
        XCTAssertTrue(save_result);

        auto const &entity_objects = save_result.value();
        XCTAssertGreaterThan(entity_objects.count("sample_a"), 0);

        auto const &objects = entity_objects.at("sample_a");
        XCTAssertEqual(objects.size(), 1);

        auto const &obj = objects.begin()->second;
        XCTAssertEqual(obj.save_id(), db::value{3});
        XCTAssertEqual(obj.get("name"), db::value::empty());
        XCTAssertEqual(obj.get("age"), db::value{10});
        XCTAssertTrue(obj.is_removed());
        XCTAssertEqual(obj.status(), db::object_status::saved);

        [exp4 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.save_id(), 3);
}

- (void)test_make_setup_error {
    auto error = make_error(db::manager::setup_error_type::version_not_found);
    XCTAssertTrue(error);
    XCTAssertEqual(error.type(), db::manager::setup_error_type::version_not_found);
}

- (void)test_setup_error_none {
    db::manager::error<db::manager::setup_error_type> error{nullptr};
    XCTAssertFalse(error);
    XCTAssertEqual(error.type(), db::manager::setup_error_type::none);
}

- (void)test_make_insert_error {
    auto error = make_error(db::manager::insert_error_type::select_failed);
    XCTAssertTrue(error);
    XCTAssertEqual(error.type(), db::manager::insert_error_type::select_failed);
}

- (void)test_insert_error_none {
    db::manager::error<db::manager::insert_error_type> error{nullptr};
    XCTAssertFalse(error);
    XCTAssertEqual(error.type(), db::manager::insert_error_type::none);
}

- (void)test_make_save_error {
    db::error database_error{db::error_type::closed, SQLITE_ERROR, "test_error_message"};

    auto error = make_error(db::manager::save_error_type::insert_failed, database_error);
    XCTAssertTrue(error);
    XCTAssertEqual(error.type(), db::manager::save_error_type::insert_failed);
    XCTAssertEqual(error.database_error().type(), db::error_type::closed);
    XCTAssertEqual(error.database_error().code().raw_value(), SQLITE_ERROR);
    XCTAssertEqual(error.database_error().message(), "test_error_message");
}

- (void)test_save_error_none {
    db::manager::error<db::manager::save_error_type> error{nullptr};
    XCTAssertFalse(error);
    XCTAssertEqual(error.type(), db::manager::save_error_type::none);
}

- (void)test_to_string_from_setup_error {
    XCTAssertEqual(to_string(db::manager::setup_error_type::begin_transaction_failed), "begin_transaction_failed");
    XCTAssertEqual(to_string(db::manager::setup_error_type::select_info_failed), "select_info_failed");
    XCTAssertEqual(to_string(db::manager::setup_error_type::update_info_failed), "update_info_failed");
    XCTAssertEqual(to_string(db::manager::setup_error_type::version_not_found), "version_not_found");
    XCTAssertEqual(to_string(db::manager::setup_error_type::invalid_version_text), "invalid_version_text");
    XCTAssertEqual(to_string(db::manager::setup_error_type::alter_entity_table_failed), "alter_entity_table_failed");
    XCTAssertEqual(to_string(db::manager::setup_error_type::create_info_table_failed), "create_info_table_failed");
    XCTAssertEqual(to_string(db::manager::setup_error_type::insert_info_failed), "insert_info_failed");
    XCTAssertEqual(to_string(db::manager::setup_error_type::create_entity_table_failed), "create_entity_table_failed");
    XCTAssertEqual(to_string(db::manager::setup_error_type::create_relation_table_failed),
                   "create_relation_table_failed");
    XCTAssertEqual(to_string(db::manager::setup_error_type::none), "none");
}

- (void)test_to_string_from_insert_error {
    XCTAssertEqual(to_string(db::manager::insert_error_type::insert_failed), "insert_failed");
    XCTAssertEqual(to_string(db::manager::insert_error_type::select_failed), "select_failed");
    XCTAssertEqual(to_string(db::manager::insert_error_type::save_id_not_found), "save_id_not_found");
    XCTAssertEqual(to_string(db::manager::insert_error_type::update_save_id_failed), "update_save_id_failed");
    XCTAssertEqual(to_string(db::manager::insert_error_type::none), "none");
}

- (void)test_to_string_from_save_error {
    XCTAssertEqual(to_string(db::manager::save_error_type::save_id_not_found), "save_id_not_found");
    XCTAssertEqual(to_string(db::manager::save_error_type::update_save_id_failed), "update_save_id_failed");
    XCTAssertEqual(to_string(db::manager::save_error_type::insert_failed), "insert_failed");
    XCTAssertEqual(to_string(db::manager::save_error_type::none), "none");
}

@end
