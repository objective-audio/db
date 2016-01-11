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

        db::column_vector args{db::value{"value_a"}, db::value{"value_b"}};
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
        auto select_infos_result = db::select(db, db::info_table, {"*"});
        XCTAssertTrue(select_infos_result);
        XCTAssertEqual(select_infos_result.value().size(), 1);
        XCTAssertEqual(select_infos_result.value().at(0).at(db::version_field).get<db::text>(), "0.0.1");

        XCTAssertTrue(db::table_exists(db, "sample_a"));
        auto select_result_a = db::select(db, "sample_a", {"*"});
        XCTAssertTrue(select_result_a);
        XCTAssertEqual(select_result_a.value().size(), 0);

        XCTAssertTrue(db::table_exists(db, "rel_sample_a_child"));
        auto select_rels_result = db::select(db, "rel_sample_a_child", {"*"});
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

        auto select_result_a = db::select(db, "sample_a", {db::id_field});
        auto &src_id = select_result_a.value().at(0).at(db::id_field);

        auto select_result_b = db::select(db, "sample_b", {db::id_field});
        auto &tgt_id = select_result_b.value().at(0).at(db::id_field);

        auto sql = db::insert_sql("rel_sample_a_child", {db::src_id_field, db::tgt_id_field});
        if (!db.execute_update(sql, db::column_vector{src_id, tgt_id})) {
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
        auto select_infos_result = db::select(db, db::info_table, {"*"});
        XCTAssertTrue(select_infos_result);
        XCTAssertEqual(select_infos_result.value().size(), 1);
        XCTAssertEqual(select_infos_result.value().at(0).at(db::version_field).get<db::text>(), "0.0.2");
        XCTAssertEqual(select_infos_result.value().at(0).at(db::save_id_field).get<db::integer>(), 100);

        XCTAssertTrue(db::table_exists(db, "sample_a"));
        auto select_result_a = db::select(db, "sample_a", {"*"});
        XCTAssertTrue(select_result_a);
        XCTAssertEqual(select_result_a.value().size(), 1);

        auto const &sample_a = select_result_a.value().at(0);
        XCTAssertEqual(sample_a.at("age").get<db::integer>(), 2);
        XCTAssertEqual(sample_a.at("name").get<db::text>(), "xyz");
        XCTAssertEqual(sample_a.at("weight").get<db::real>(), 451.2);

        XCTAssertTrue(db::table_exists(db, "sample_b"));
        auto select_result_b = db::select(db, "sample_b", {"*"});
        XCTAssertTrue(select_result_b);
        XCTAssertEqual(select_result_b.value().size(), 1);

        auto const &sample_b = select_result_b.value().at(0);
        XCTAssertEqual(sample_b.at("name").get<db::text>(), "qwerty");

        XCTAssertTrue(db::table_exists(db, "sample_c"));
        auto select_result_c = db::select(db, "sample_c", {"*"});
        XCTAssertTrue(select_result_c);
        XCTAssertEqual(select_result_c.value().size(), 0);

        XCTAssertTrue(db::table_exists(db, "rel_sample_a_child"));
        auto select_rels_result = db::select(db, "rel_sample_a_child", {"*"});
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

    manager.insert_objects("sample_a", 3, [self, expectation_1](auto const &insert_result) {
        XCTAssertTrue(insert_result);

        auto const &objects = insert_result.value();

        XCTAssertEqual(objects.size(), 3);
        XCTAssertEqual(objects.at(0).object_id(), db::value{1});
        XCTAssertEqual(objects.at(1).object_id(), db::value{2});
        XCTAssertEqual(objects.at(2).object_id(), db::value{3});

        XCTAssertEqual(objects.at(0).save_id(), db::value{1});
        XCTAssertEqual(objects.at(1).save_id(), db::value{1});
        XCTAssertEqual(objects.at(2).save_id(), db::value{1});

        [expectation_1 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.save_id(), 1);

    XCTestExpectation *expectation_2 = [self expectationWithDescription:@"insert_2"];

    manager.insert_objects("sample_a", 1, [self, expectation_2](auto const &insert_result) {
        XCTAssertTrue(insert_result);

        auto const &objects = insert_result.value();

        XCTAssertEqual(objects.size(), 1);
        XCTAssertEqual(objects.at(0).object_id(), db::value{4});

        XCTAssertEqual(objects.at(0).save_id(), db::value{2});

        [expectation_2 fulfill];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(manager.save_id(), 2);

    auto &object_1 = manager.cached_object("sample_a", 1);
    XCTAssertTrue(object_1);
    XCTAssertEqual(object_1.object_id(), db::value{1});

    XCTAssertFalse(manager.cached_object("sample_a", 5));
}

@end
