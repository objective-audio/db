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

    manager.execute([self, exp](auto &database, auto const &operation) {
        XCTAssertTrue(database);
        XCTAssertTrue(operation);
        XCTAssertFalse([NSThread isMainThread]);
        [exp fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_execute_update_and_query_in_bg {
    auto manager = [yas_db_test_utils create_test_manager];

    XCTestExpectation *exp = [self expectationWithDescription:@"execution"];

    manager.execute([self, exp](db::manager &manager, auto const &operation) {
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

        [exp fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_setup {
    db::model model{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model)];

    XCTestExpectation *exp = [self expectationWithDescription:@"setup"];

    manager.setup([self](auto &, auto result) { XCTAssertTrue(result); });

    manager.execute([self, exp](db::manager &manager, auto const &op) {
        auto &db = manager.database();

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

        XCTAssertTrue(db::index_exists(db, "sample_a_name"));
        XCTAssertTrue(db::index_exists(db, "sample_a_others"));
        XCTAssertFalse(db::index_exists(db, "sample_b_name"));

        [exp fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_setup_migration {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *exp1 = [self expectationWithDescription:@"setup_1"];

    manager.setup([self](auto &, auto result) { XCTAssertTrue(result); });

    manager.execute([self, exp1](db::manager &manager, auto const &) {
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

        db::select_option option{.fields = {db::id_field}};

        auto select_result_a = db::select(db, "sample_a", option);
        auto &src_id = select_result_a.value().at(0).at(db::id_field);

        auto select_result_b = db::select(db, "sample_b", option);
        auto &tgt_id = select_result_b.value().at(0).at(db::id_field);

        auto sql = db::insert_sql("rel_sample_a_child", {db::src_id_field, db::tgt_id_field});
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

        [exp1 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    manager = nullptr;

    XCTestExpectation *exp2 = [self expectationWithDescription:@"setup_2"];

    db::model model_0_0_2{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_2]};
    manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self](auto &, auto result) { XCTAssertTrue(result); });

    manager.execute([self, exp2](db::manager &manager, auto const &) {
        auto &db = manager.database();

        XCTAssertTrue(db::table_exists(db, db::info_table));
        auto select_infos_result = db::select(db, db::info_table);
        XCTAssertTrue(select_infos_result);
        XCTAssertEqual(select_infos_result.value().size(), 1);
        XCTAssertEqual(select_infos_result.value().at(0).at(db::version_field).get<db::text>(), "0.0.2");
        XCTAssertEqual(select_infos_result.value().at(0).at(db::current_save_id_field).get<db::integer>(), 100);
        XCTAssertEqual(select_infos_result.value().at(0).at(db::last_save_id_field).get<db::integer>(), 100);

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

        XCTAssertTrue(db::index_exists(db, "sample_a_name"));
        XCTAssertTrue(db::index_exists(db, "sample_a_others"));
        XCTAssertTrue(db::index_exists(db, "sample_b_name"));

        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_insert_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *exp1 = [self expectationWithDescription:@"insert_1"];

    manager.setup([self](auto &manager, auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), 0);
        XCTAssertEqual(manager.last_save_id(), 0);
    });

    db::object_vector_map inserted_objects_1;

    manager.insert_objects(
        [](auto &) {
            return db::entity_count_map{{"sample_a", 3}};
        },
        [self, exp1, &inserted_objects_1](auto &manager, auto result) {
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

    XCTAssertEqual(manager.current_save_id(), 1);
    XCTAssertEqual(manager.last_save_id(), 1);

    XCTestExpectation *exp2 = [self expectationWithDescription:@"insert_2"];

    db::object_vector_map inserted_objects_2;

    manager.insert_objects(
        [](auto &) {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, exp2, &inserted_objects_2](auto &manager, auto result) {
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

    XCTAssertEqual(manager.current_save_id(), 2);
    XCTAssertEqual(manager.last_save_id(), 2);

    auto const object_1 = manager.cached_object("sample_a", 1);
    XCTAssertTrue(object_1);
    XCTAssertEqual(object_1.object_id(), db::value{1});

    XCTAssertFalse(manager.cached_object("sample_a", 5));
}

- (void)test_insert_many_entity_objects {
    db::model model_0_0_2{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_2]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self](auto &, auto result) { XCTAssertTrue(result); });

    XCTestExpectation *exp1 = [self expectationWithDescription:@"insert_1"];

    manager.insert_objects(
        [](auto &) {
            return db::entity_count_map{{"sample_a", 3}, {"sample_b", 5}};
        },
        [self, exp1](auto &, auto result) {
            db::object_vector_map const &objects = result.value();
            XCTAssertEqual(objects.size(), 2);

            XCTAssertGreaterThan(objects.count("sample_a"), 0);

            db::object_vector const &a_objects = objects.at("sample_a");
            XCTAssertEqual(a_objects.size(), 3);

            XCTAssertGreaterThan(objects.count("sample_b"), 0);

            db::object_vector const &b_objects = objects.at("sample_b");
            XCTAssertEqual(b_objects.size(), 5);

            [exp1 fulfill];
        });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_fetch_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self](auto &manager, auto result) { XCTAssertTrue(result); });

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];

    db::object_vector_map objects;

    manager.insert_objects(
        [](auto &) {
            return db::entity_count_map{{"sample_a", 3}, {"sample_b", 2}};
        },
        [self, exp1, &objects](auto &, auto result) {
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

    XCTAssertEqual(manager.current_save_id(), 1);
    XCTAssertEqual(manager.last_save_id(), 1);
    objects.at("sample_a").at(1).set_attribute("name", db::value{"value_1"});
    objects.at("sample_a").at(1).push_back_relation_id("child", objects.at("sample_b").at(0).object_id());

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.save([self, exp2](auto &, auto save_result) {
        XCTAssertTrue(save_result);

        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), 2);
    XCTAssertEqual(manager.last_save_id(), 2);

    XCTestExpectation *exp3 = [self expectationWithDescription:@"3"];

    manager.fetch_objects("sample_a", {},
                          [self, exp3](auto &, auto fetch_result) {
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

    manager.save([self, exp4](auto &, auto save_result) { [exp4 fulfill]; });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), 3);
    XCTAssertEqual(manager.last_save_id(), 3);

    XCTestExpectation *exp5 = [self expectationWithDescription:@"4"];

    db::select_option option{.where_exprs = db::field_expr("name", "like"),
                             .arguments = {{"name", db::value{"value_%"}}},
                             .field_orders = {{db::object_id_field, db::order::descending}},
                             .limit_range = db::range{0, 3}};

    manager.fetch_objects("sample_a", std::move(option), [self, exp5, &objects](auto &, auto fetch_result) {
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

        [exp5 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_fetch_const_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *exp = [self expectationWithDescription:@"1"];

    yas::chain(nullptr, {[self, manager](auto context) mutable {
                             manager.setup([self, context](auto &manager, auto result) mutable {
                                 XCTAssertTrue(result);

                                 context.next();
                             });
                         },
                         [self, manager](auto context) mutable {
                             manager.insert_objects(
                                 [](auto &) {
                                     return db::entity_count_map{{"sample_a", 1}, {"sample_b", 1}};
                                 },
                                 [self, context](auto &manager, auto result) mutable {
                                     XCTAssertTrue(result);
                                     auto &objects = result.value();

                                     XCTAssertEqual(manager.current_save_id(), 1);
                                     XCTAssertEqual(manager.last_save_id(), 1);

                                     objects.at("sample_a").at(0).set_attribute("name", db::value{"value_0"});

                                     auto &object_b = objects.at("sample_b").at(0);
                                     objects.at("sample_a").at(0).push_back_relation_id("child", object_b.object_id());

                                     XCTAssertEqual(object_b.object_id(), db::value{1});

                                     context.next();
                                 });
                         },
                         [self, manager](auto context) mutable {
                             manager.save([self, context](auto &, auto save_result) mutable {
                                 XCTAssertTrue(save_result);

                                 context.next();
                             });
                         },
                         [self, manager, exp](auto context) mutable {
                             manager.fetch_const_objects(
                                 "sample_a", {},
                                 [self, exp, context](auto &, db::manager::const_vector_result_t fetch_result) mutable {
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

                                     context.next();

                                     [exp fulfill];
                                 });
                         }});

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_fetch_relation_objects {
    db::model model_0_0_2{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_2]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self](auto &manager, auto result) { XCTAssertTrue(result); });

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];

    manager.insert_objects(
        [](auto &) {
            return db::entity_count_map{{"sample_a", 1}, {"sample_b", 1}, {"sample_c", 1}};
        },
        [self, exp1](auto &, auto result) {
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

    manager.save([self, exp2](db::manager &manager, auto save_result) {
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

    manager.fetch_objects("sample_a", db::select_option{},
                          [self, exp3, &object_a](auto &, auto const &fetch_result) {
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

    XCTestExpectation *exp4 = [self expectationWithDescription:@"4"];

    manager.fetch_objects(
        db::relation_ids(db::object_vector_map{std::make_pair("sample_a", db::object_vector{object_a})}),
        [self, exp4, object_a](db::manager &manager, auto const &fetch_result) {
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

            [exp4 fulfill];
        });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_fetch_const_objects_by_ids {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *exp = [self expectationWithDescription:@"1"];

    yas::chain(nullptr, {[self, manager](auto context) mutable {
                             manager.setup([self, context](auto &manager, auto result) mutable {
                                 XCTAssertTrue(result);

                                 context.next();
                             });
                         },
                         [self, manager](auto context) mutable {
                             manager.insert_objects(
                                 [](auto &) {
                                     return db::entity_count_map{{"sample_a", 3}};
                                 },
                                 [self, context](auto &manager, auto result) mutable {
                                     XCTAssertTrue(result);
                                     auto &objects = result.value();

                                     XCTAssertEqual(manager.current_save_id(), 1);
                                     XCTAssertEqual(manager.last_save_id(), 1);

                                     objects.at("sample_a").at(0).set_attribute("name", db::value{"value_1"});
                                     objects.at("sample_a").at(1).set_attribute("name", db::value{"value_2"});
                                     objects.at("sample_a").at(2).set_attribute("name", db::value{"value_3"});

                                     XCTAssertEqual(objects.at("sample_a").at(0).object_id(), db::value{1});
                                     XCTAssertEqual(objects.at("sample_a").at(1).object_id(), db::value{2});
                                     XCTAssertEqual(objects.at("sample_a").at(2).object_id(), db::value{3});

                                     context.next();
                                 });
                         },
                         [self, manager](auto context) mutable {
                             manager.save([self, context](auto &, auto save_result) mutable {
                                 XCTAssertTrue(save_result);

                                 context.next();
                             });
                         },
                         [self, manager, exp](auto context) mutable {
                             db::integer_set_map obj_ids{{"sample_a", {2}}};

                             manager.fetch_const_objects(
                                 std::move(obj_ids), [self, exp, context](auto &, auto fetch_result) mutable {
                                     XCTAssertTrue(fetch_result);

                                     auto const &objects = fetch_result.value();
                                     XCTAssertEqual(objects.count("sample_a"), 1);
                                     auto &a_objects = objects.at("sample_a");
                                     XCTAssertEqual(a_objects.size(), 1);
                                     XCTAssertEqual(a_objects.at(2).object_id(), db::value{2});
                                     XCTAssertEqual(a_objects.at(2).get_attribute("name"), db::value{"value_2"});

                                     context.next();

                                     [exp fulfill];
                                 });
                         }});

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_save_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self](auto &manager, auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), 0);
        XCTAssertEqual(manager.last_save_id(), 0);
    });

    std::unordered_map<db::integer::type, db::object> main_objects;

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];

    manager.insert_objects(
        [](auto &) {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [self, &main_objects, exp1](auto &, auto result) {
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

    XCTAssertEqual(manager.current_save_id(), 1);
    XCTAssertEqual(manager.last_save_id(), 1);

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.save([self, exp2](auto &, auto save_result) {
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

    manager.save([self, exp3](auto &, auto save_result) {
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

    manager.execute([self, exp3](db::manager &manager, operation const &) {
        auto &db = manager.database();

        auto value_result = db::select(db, "sample_a");
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

        auto relation_result = db::select(db, manager.model().relation("sample_a", "child").table_name);
        auto const &selected_relations = relation_result.value();

        XCTAssertEqual(selected_relations.size(), 2);
        XCTAssertEqual(selected_relations.at(0).at(db::tgt_id_field), db::value{100});
        XCTAssertEqual(selected_relations.at(1).at(db::tgt_id_field), db::value{200});

        [exp3 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), 2);
    XCTAssertEqual(manager.last_save_id(), 2);
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

    manager.save([self, exp4](auto &, auto save_result) {
        XCTAssertTrue(save_result);

        auto const &objects = save_result.value();
        XCTAssertGreaterThan(objects.count("sample_a"), 0);

        auto const &a_objects = objects.at("sample_a");
        XCTAssertEqual(a_objects.size(), 1);

        auto const &obj = a_objects.at(0);
        XCTAssertEqual(obj.save_id(), db::value{3});
        XCTAssertEqual(obj.get_attribute("name"), db::value::empty());
        XCTAssertEqual(obj.get_attribute("age"), db::value{10});
        XCTAssertEqual(obj.relation_size("child"), 0);
        XCTAssertEqual(obj.get_relation_ids("child").size(), 0);
        XCTAssertTrue(obj.is_removed());
        XCTAssertEqual(obj.status(), db::object_status::saved);
        XCTAssertEqual(obj.action(), db::value{db::remove_action});

        [exp4 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), 3);
    XCTAssertEqual(manager.last_save_id(), 3);

    XCTestExpectation *exp5 = [self expectationWithDescription:@"5"];

    manager.save([self, exp5](auto &, auto save_result) {
        XCTAssertTrue(save_result);

        auto const &objects = save_result.value();
        XCTAssertEqual(objects.size(), 0);

        [exp5 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), 3);
    XCTAssertEqual(manager.last_save_id(), 3);
}

- (void)test_revert_objects {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];

    yas::chain(db::object{nullptr},
               {[self, &manager](auto context) mutable {
                    manager.setup([self](auto &manager, auto result) {
                        XCTAssertTrue(result);
                        XCTAssertEqual(manager.current_save_id(), 0);
                        XCTAssertEqual(manager.last_save_id(), 0);
                    });

                    context.next();
                },
                [self, &manager](auto context) mutable {
                    manager.insert_objects(
                        [](auto &) {
                            return db::entity_count_map{{"sample_a", 1}};
                        },
                        [self, context](auto &, auto result) mutable {
                            auto &a_object = context.get();
                            a_object = result.value().at("sample_a").at(0);

                            context.next();
                        });
                },
                [self, &manager](auto context) mutable {
                    auto &a_object = context.get();

                    XCTAssertEqual(a_object.save_id(), db::value{1});

                    a_object.set_attribute("name", db::value{"value_2"});

                    manager.save([context](auto &, auto) mutable { context.next(); });
                },
                [self, &manager](auto context) mutable {
                    auto &a_object = context.get();

                    XCTAssertEqual(a_object.save_id(), db::value{2});

                    a_object.remove();

                    manager.save([context](auto &, auto const &) mutable { context.next(); });
                },
                [self, &manager](auto context) mutable {
                    auto &a_object = context.get();

                    XCTAssertEqual(a_object.save_id(), db::value{3});
                    XCTAssertTrue(a_object.is_removed());

                    manager.revert(2, [context](auto &, auto const &) mutable { context.next(); });
                },
                [self, &manager](auto context) mutable {
                    auto &a_object = context.get();

                    XCTAssertEqual(a_object.save_id(), db::value{2});
                    XCTAssertEqual(a_object.get_attribute("name"), db::value{"value_2"});
                    XCTAssertFalse(a_object.is_removed());

                    manager.revert(1, [context](auto &, auto const &) mutable { context.next(); });
                },
                [self, &manager](auto context) mutable {
                    auto &a_object = context.get();

                    XCTAssertEqual(a_object.save_id(), db::value{1});
                    XCTAssertEqual(a_object.get_attribute("name"), db::value{"default_value"});

                    a_object.set_attribute("name", db::value{"value_b"});

                    manager.save([context](auto &, auto const &) mutable { context.next(); });
                },
                [self, &manager](auto context) mutable {
                    manager.execute([self, context](db::manager &manager, operation const &) mutable {
                        auto &db = manager.database();

                        auto select_result = db::select(
                            db, "sample_a", db::select_option{.where_exprs = db::expr(db::save_id_field, "=", "3")});
                        XCTAssertTrue(select_result);
                        XCTAssertEqual(select_result.value().size(), 0);

                        select_result = db::select(
                            db, "sample_a", db::select_option{.where_exprs = db::expr(db::save_id_field, "=", "2")});
                        XCTAssertTrue(select_result);
                        XCTAssertEqual(select_result.value().size(), 1);

                        select_result = db::select(
                            db, "sample_a", db::select_option{.where_exprs = db::expr(db::save_id_field, "=", "1")});
                        XCTAssertTrue(select_result);
                        XCTAssertEqual(select_result.value().size(), 1);

                        context.next();
                    });
                },
                [self, &manager](auto context) mutable {
                    manager.revert(0, [context](auto &, auto const &) mutable { context.next(); });
                },
                [self, &manager, exp](auto context) mutable {
                    auto &a_object = context.get();

                    XCTAssertEqual(a_object.status(), db::object_status::invalid);
                    XCTAssertFalse(a_object.save_id());
                    XCTAssertFalse(a_object.action());
                    XCTAssertFalse(a_object.get_attribute("name"));

                    context.next();

                    [exp fulfill];
                }});

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_restore_reverted_db {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    if (auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)]) {
        XCTestExpectation *exp1 = [self expectationWithDescription:@"exp1"];

        yas::chain(db::object_vector_map{},
                   {[self, manager](auto context) mutable {
                        manager.setup([self, context](auto &manager, auto result) mutable {
                            XCTAssertTrue(result);
                            XCTAssertEqual(manager.current_save_id(), 0);
                            XCTAssertEqual(manager.last_save_id(), 0);

                            context.next();
                        });
                    },
                    [self, manager](auto context) mutable {
                        manager.insert_objects(
                            [](auto &) {
                                return db::entity_count_map{{"sample_a", 1}, {"sample_b", 2}};
                            },
                            [self, context](auto &manager, auto result) mutable {
                                XCTAssertTrue(result);
                                XCTAssertEqual(manager.current_save_id(), 1);
                                XCTAssertEqual(manager.last_save_id(), 1);

                                auto &objects = context.get();
                                objects = std::move(result.value());

                                objects.at("sample_a").at(0).set_attribute("name", db::value{"name_value_1"});
                                objects.at("sample_b").at(0).set_attribute("name", db::value{"name_value_2"});
                                objects.at("sample_b").at(1).set_attribute("name", db::value{"name_value_3"});

                                context.next();
                            });
                    },
                    [self, manager](auto context) mutable {
                        manager.save([self, context](auto &manager, auto result) mutable {
                            XCTAssertTrue(result);
                            XCTAssertEqual(manager.current_save_id(), 2);
                            XCTAssertEqual(manager.last_save_id(), 2);

                            auto &objects = context.get();
                            objects.at("sample_a").at(0).set_attribute("name", db::value{"name_value_4"});
                            objects.at("sample_b").at(0).set_attribute("name", db::value{"name_value_5"});
                            objects.at("sample_a").at(0).set_relation_object("child", {objects.at("sample_b").at(0)});
                            XCTAssertEqual(objects.at("sample_b").at(0).object_id(), db::value{1});

                            context.next();
                        });
                    },
                    [self, manager](auto context) mutable {
                        manager.save([self, context](auto &manager, auto result) mutable {
                            XCTAssertTrue(result);
                            XCTAssertEqual(manager.current_save_id(), 3);
                            XCTAssertEqual(manager.last_save_id(), 3);

                            auto &objects = context.get();

                            objects.at("sample_a").at(0).set_attribute("name", db::value{"name_value_6"});
                            objects.at("sample_b").at(1).set_attribute("name", db::value{"name_value_7"});
                            objects.at("sample_a").at(0).set_relation_object("child", {objects.at("sample_b").at(1)});

                            context.next();
                        });
                    },
                    [self, manager](auto context) mutable {
                        manager.save([self, context](auto &manager, auto result) mutable {
                            XCTAssertTrue(result);
                            XCTAssertEqual(manager.current_save_id(), 4);
                            XCTAssertEqual(manager.last_save_id(), 4);

                            context.next();
                        });
                    },
                    [self, manager](auto context) mutable {
                        manager.revert(3, [self, context](auto &manager, auto result) mutable {
                            XCTAssertTrue(result);
                            XCTAssertEqual(manager.current_save_id(), 3);
                            XCTAssertEqual(manager.last_save_id(), 4);

                            context.next();
                        });
                    },
                    [self, manager, exp1](auto context) mutable { [exp1 fulfill]; }});

        [self waitForExpectationsWithTimeout:1.0 handler:nil];
    } else {
        XCTAssert(0);
    }

    if (auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)]) {
        XCTestExpectation *exp2 = [self expectationWithDescription:@"exp2"];

        yas::chain(
            db::object_vector_map{},
            {[self, manager](auto context) mutable {
                 manager.setup([self, context](auto &manager, auto result) mutable {
                     XCTAssertTrue(result);
                     XCTAssertEqual(manager.current_save_id(), 3);
                     XCTAssertEqual(manager.last_save_id(), 4);

                     context.next();
                 });
             },
             [self, manager](auto context) mutable {
                 manager.fetch_objects("sample_a", {},
                                       [self, context](auto &manager, auto result) mutable {
                                           XCTAssertTrue(result);

                                           auto &objects = context.get();
                                           objects = std::move(result.value());

                                           XCTAssertEqual(objects.count("sample_a"), 1);
                                           XCTAssertEqual(objects.at("sample_a").at(0).get_attribute("name"),
                                                          db::value{"name_value_4"});
                                           XCTAssertEqual(objects.at("sample_a").at(0).relation_size("child"), 1);

                                           context.next();
                                       });
             },
             [self, manager](auto context) mutable {
                 manager.fetch_objects(db::relation_ids(context.get()), [self, context](auto &manager,
                                                                                        auto result) mutable {
                     XCTAssertTrue(result);

                     db::object_map_map &rel_objects = result.value();

                     XCTAssertEqual(rel_objects.count("sample_b"), 1);
                     XCTAssertEqual(rel_objects.at("sample_b").at(1).get_attribute("name"), db::value{"name_value_5"});

                     auto &objects = context.get();

                     auto sample_bs =
                         to_vector<db::object>(rel_objects.at("sample_b"), [](auto &pair) { return pair.second; });
                     objects.emplace(std::make_pair("sample_b", std::move(sample_bs)));

                     context.next();
                 });
             },
             [self, exp2](auto context) mutable {
                 auto &objects = context.get();

                 XCTAssertEqual(objects.at("sample_a").at(0).get_relation_object("child", 0).get_attribute("name"),
                                db::value{"name_value_5"});

                 context.next();

                 [exp2 fulfill];
             }});

        [self waitForExpectationsWithTimeout:1.0 handler:nil];
    } else {
        XCTAssert(0);
    }
}

- (void)test_suspend_and_priority {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1) priority_count:2];

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];
    manager.setup([exp1](auto &, auto) { [exp1 fulfill]; });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.suspend();

    int call_count = 0;
    int fetched_object_count = 0;

    manager.insert_objects(
        [](auto &) {
            return db::entity_count_map{{"sample_a", 1}};
        },
        [&call_count, exp2](auto &, auto) {
            call_count++;
            if (call_count == 2) {
                [exp2 fulfill];
            }
        },
        1);

    manager.fetch_objects("sample_a", {},
                          [&call_count, exp2, &fetched_object_count, self](auto &, auto result) {
                              XCTAssertTrue(result);
                              XCTAssertEqual(result.value().count("sample_a"), 0);

                              call_count++;
                              if (call_count == 2) {
                                  [exp2 fulfill];
                              }
                          },
                          0);

    manager.resume();

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
    XCTAssertEqual(to_string(db::manager::error_type::select_last_failed), "select_last_failed");
    XCTAssertEqual(to_string(db::manager::error_type::select_revert_failed), "select_revert_failed");
    XCTAssertEqual(to_string(db::manager::error_type::fetch_object_datas_failed), "fetch_object_datas_failed");
    XCTAssertEqual(to_string(db::manager::error_type::out_of_range_save_id), "out_of_range_save_id");
    XCTAssertEqual(to_string(db::manager::error_type::select_failed), "select_failed");
    XCTAssertEqual(to_string(db::manager::error_type::none), "none");
}

@end
