//
//  yas_db_manager_tests.mm
//

#import <cpp_utils/yas_fast_each.h>
#import <cpp_utils/yas_objc_ptr.h>
#import <db/yas_db_manager_utils.h>
#import <db/yas_db_utils.h>
#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_manager_tests : XCTestCase

@end

@implementation yas_db_manager_tests

- (void)setUp {
    [super setUp];
    [yas_db_test_utils deleteDatabase];
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

    manager.execute(db::no_cancellation, [self, exp](auto const &task) {
        XCTAssertFalse([NSThread isMainThread]);
        [exp fulfill];
    });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_execute_update_and_query_in_bg {
    auto manager = [yas_db_test_utils create_test_manager];

    manager.execute(db::no_cancellation, [self, &manager](task const &) {
        auto &db = manager.database();

        XCTAssertTrue(db.execute_update(db::create_table_sql("test_table", {"field_a", "field_b"})));

        db::value_vector_t args{db::value{"value_a"}, db::value{"value_b"}};
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
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_setup {
    db::model model = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.execute(db::no_cancellation, [self, &manager](auto const &) {
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
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_create_object {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    db::object_vector_t objects;

    manager.setup([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);

        objects.emplace_back(manager.create_object("sample_a"));
        objects.emplace_back(manager.create_object("sample_a"));

        for (auto const &idx : make_each_index(2)) {
            auto const &object = objects[idx];

            XCTAssertEqual(object.status(), db::object_status::created);
            XCTAssertTrue(object.object_id().is_temporary());
            XCTAssertEqual(object.attribute_value(db::action_field), db::insert_action_value());
            XCTAssertEqual(object.attribute_value("name"), db::value{"default_value"});
            XCTAssertEqual(object.attribute_value("age"), db::value{10});
            XCTAssertEqual(object.attribute_value("weight"), db::value{65.4});

            XCTAssertFalse(object.attribute_value(db::pk_id_field));
            XCTAssertEqual(object.attribute_value(db::save_id_field), db::value{0});
        }

        objects[0].set_attribute_value("name", db::value{"test_name_0_created"});
        objects[1].set_attribute_value("name", db::value{"test_name_1_created"});

        XCTAssertEqual(objects[0].status(), db::object_status::created);
        XCTAssertEqual(objects[1].status(), db::object_status::created);

        XCTAssertTrue(manager.has_created_objects());
        XCTAssertEqual(manager.created_object_count("sample_a"), 2);
    });

    manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{1});

        db::object_map_t &a_objects = result.value().at("sample_a");
        XCTAssertEqual(a_objects.size(), 2);

        auto each = make_fast_each(objects.size());
        while (yas_each_next(each)) {
            auto const &idx = yas_each_index(each);
            auto const &object = objects.at(idx);
            auto const &saved_object = a_objects.at(object.object_id().stable());

            XCTAssertEqual(saved_object, object);
            XCTAssertTrue(saved_object.object_id().stable_value());

            XCTAssertEqual(saved_object.status(), db::object_status::saved);
            XCTAssertEqual(saved_object.attribute_value(db::action_field), db::insert_action_value());
            XCTAssertEqual(saved_object.attribute_value("age"), db::value{10});
            XCTAssertEqual(saved_object.attribute_value("weight"), db::value{65.4});

            XCTAssertEqual(saved_object.attribute_value(db::save_id_field), db::value{1});

            if (idx == 0) {
                XCTAssertEqual(saved_object.attribute_value("name"), db::value{"test_name_0_created"});
            } else if (idx == 1) {
                XCTAssertEqual(saved_object.attribute_value("name"), db::value{"test_name_1_created"});
            }
        }

        XCTAssertFalse(manager.has_created_objects());
        XCTAssertEqual(manager.created_object_count("sample_a"), 0);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_create_and_save_objects {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    db::object_vector_t objects{};

    manager.setup([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);

        objects.emplace_back(manager.create_object("sample_a"));
        objects.emplace_back(manager.create_object("sample_a"));

        objects[0].set_attribute_value("name", db::value{"test_name_0_created"});
        objects[1].set_attribute_value("name", db::value{"test_name_1_created"});

        XCTAssertTrue(manager.has_created_objects());
        XCTAssertEqual(manager.created_object_count("sample_a"), 2);
    });

    manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertFalse(manager.has_created_objects());

        XCTAssertEqual(objects[0].status(), db::object_status::saved);
        XCTAssertEqual(objects[1].status(), db::object_status::saved);
        XCTAssertTrue(manager.cached_or_created_object("sample_a", objects[0].object_id()));
        XCTAssertTrue(manager.cached_or_created_object("sample_a", objects[1].object_id()));

        objects[0].set_attribute_value("name", db::value{"test_name_0_saved"});
        objects[0].set_attribute_value("age", db::value{0});
        objects[1].set_attribute_value("name", db::value{"test_name_1_saved"});
        objects[1].set_attribute_value("age", db::value{1});

        XCTAssertEqual(objects[0].status(), db::object_status::changed);
        XCTAssertEqual(objects[1].status(), db::object_status::changed);

        XCTAssertTrue(manager.has_changed_objects());
        XCTAssertEqual(manager.changed_object_count("sample_a"), 2);
        XCTAssertFalse(manager.has_created_objects());
        XCTAssertEqual(manager.created_object_count("sample_a"), 0);

        objects.emplace_back(manager.create_object("sample_a"));
        objects.emplace_back(manager.create_object("sample_a"));

        objects[2].set_attribute_value("name", db::value{"test_name_2_created"});
        objects[2].set_attribute_value("age", db::value{2});
        objects[3].set_attribute_value("name", db::value{"test_name_3_created"});
        objects[3].set_attribute_value("age", db::value{3});

        XCTAssertTrue(manager.has_created_objects());
    });

    manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) {
        XCTAssertTrue(result);

        XCTAssertEqual(objects[0].attribute_value("name"), db::value{"test_name_0_saved"});
        XCTAssertEqual(objects[1].attribute_value("name"), db::value{"test_name_1_saved"});
        XCTAssertEqual(objects[2].attribute_value("name"), db::value{"test_name_2_created"});
        XCTAssertEqual(objects[3].attribute_value("name"), db::value{"test_name_3_created"});

        XCTAssertEqual(objects[0].status(), db::object_status::saved);
        XCTAssertEqual(objects[1].status(), db::object_status::saved);
        XCTAssertEqual(objects[2].status(), db::object_status::saved);
        XCTAssertEqual(objects[3].status(), db::object_status::saved);

        XCTAssertTrue(objects[0].object_id().stable_value());
        XCTAssertTrue(objects[1].object_id().stable_value());
        XCTAssertTrue(objects[2].object_id().stable_value());
        XCTAssertTrue(objects[3].object_id().stable_value());
    });

    manager.fetch_const_objects(
        db::no_cancellation,
        []() {
            return db::to_fetch_option(db::select_option{
                .table = "sample_a", .field_orders = {db::field_order{.field = "age", .order = db::order::ascending}}});
        },
        [self, &manager](auto result) {
            XCTAssertTrue(result);

            db::const_object_vector_t &objects = result.value().at("sample_a");
            XCTAssertEqual(objects.size(), 4);

            XCTAssertEqual(objects[0].attribute_value("name"), db::value{"test_name_0_saved"});
            XCTAssertEqual(objects[1].attribute_value("name"), db::value{"test_name_1_saved"});
            XCTAssertEqual(objects[2].attribute_value("name"), db::value{"test_name_2_created"});
            XCTAssertEqual(objects[3].attribute_value("name"), db::value{"test_name_3_created"});
        });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_set_relation_to_temporary_object {
    // temporaryなオブジェクトのrelationにtemporaryなオブジェクトをセットして保存するテスト

    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *setupExp = [self expectationWithDescription:@"setup"];

    manager.setup([self, &manager, &setupExp](auto result) {
        XCTAssertTrue(result);

        [setupExp fulfill];
    });

    [self waitForExpectations:@[setupExp] timeout:10.0];

    auto object_a = manager.create_object("sample_a");
    auto object_b1 = manager.create_object("sample_b");
    auto object_b2 = manager.create_object("sample_b");

    XCTAssertTrue(object_a.object_id().is_temporary());
    XCTAssertTrue(object_b1.object_id().is_temporary());
    XCTAssertTrue(object_b2.object_id().is_temporary());

    XCTAssertNoThrow(object_a.add_relation_object("child", object_b1));
    XCTAssertNoThrow(object_a.add_relation_object("child", object_b2));

    XCTestExpectation *saveExp = [self expectationWithDescription:@"save"];

    db::object_map_map_t result_objects;

    manager.save(db::no_cancellation, [self, &result_objects, &saveExp](db::manager_map_result_t result) {
        XCTAssertTrue(result);

        result_objects = std::move(result.value());

        [saveExp fulfill];
    });

    [self waitForExpectations:@[saveExp] timeout:10.0];

    XCTAssertTrue(object_a.object_id().is_stable());
    XCTAssertTrue(object_b1.object_id().is_stable());
    XCTAssertTrue(object_b2.object_id().is_stable());

    XCTAssertEqual(object_a.relation_id("child", 0), object_b1.object_id());
    XCTAssertEqual(object_a.relation_id("child", 1), object_b2.object_id());

    XCTAssertEqual(manager.relation_object_at(object_a, "child", 0), object_b1);
    XCTAssertEqual(manager.relation_object_at(object_a, "child", 1), object_b2);

    db::object &result_object_a = result_objects.at("sample_a").begin()->second;

    XCTAssertEqual(object_a, result_object_a);
    XCTAssertTrue(result_objects.at("sample_b").count(object_b1.object_id().stable()) > 0);
    XCTAssertTrue(result_objects.at("sample_b").count(object_b2.object_id().stable()) > 0);
}

- (void)test_set_temporary_relation_to_saved_object {
    // stableなオブジェクトのrelationにtemporaryなオブジェクトをセットして保存するテスト

    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    {
        XCTestExpectation *setupExp = [self expectationWithDescription:@"setup"];

        manager.setup([self, &manager, &setupExp](auto result) {
            XCTAssertTrue(result);

            [setupExp fulfill];
        });

        [self waitForExpectations:@[setupExp] timeout:10.0];
    }

    auto object_a = manager.create_object("sample_a");

    {
        XCTestExpectation *saveExp = [self expectationWithDescription:@"save"];

        manager.save(db::no_cancellation, [self, &saveExp](db::manager_map_result_t result) {
            XCTAssertTrue(result);

            [saveExp fulfill];
        });

        [self waitForExpectations:@[saveExp] timeout:10.0];
    }

    XCTAssertTrue(object_a.object_id().is_stable());

    auto object_b = manager.create_object("sample_b");

    object_a.add_relation_object("child", object_b);

    {
        XCTestExpectation *saveExp = [self expectationWithDescription:@"save"];

        manager.save(db::no_cancellation, [self, &saveExp](db::manager_map_result_t result) {
            XCTAssertTrue(result);

            [saveExp fulfill];
        });

        [self waitForExpectations:@[saveExp] timeout:10.0];
    }

    XCTAssertTrue(object_a.relation_id("child", 0).is_stable());
    XCTAssertEqual(manager.relation_object_at(object_a, "child", 0).object_id(), object_b.object_id());
}

- (void)test_object_relation_objects {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *setup_exp = [self expectationWithDescription:@"setup manager"];

    manager.setup([setup_exp](auto result) { [setup_exp fulfill]; });

    [self waitForExpectations:@[setup_exp] timeout:10.0];

    db::object obj = manager.create_object("sample_a");
    db::object obj_b1 = manager.create_object("sample_b");
    db::object obj_b2 = manager.create_object("sample_b");
    db::object obj_b3 = manager.create_object("sample_b");

    XCTestExpectation *save_exp = [self expectationWithDescription:@"setup manager"];

    manager.save(db::no_cancellation, [save_exp](db::manager_map_result_t save_result) { [save_exp fulfill]; });

    [self waitForExpectations:@[save_exp] timeout:10.0];

    obj.add_relation_object("child", obj_b1);
    obj.add_relation_object("child", obj_b2);
    obj.add_relation_object("child", obj_b3);

    auto rel_objects = manager.relation_objects(obj, "child");

    XCTAssertEqual(rel_objects.size(), 3);

    XCTAssertTrue(rel_objects.at(0));
    XCTAssertTrue(rel_objects.at(1));
    XCTAssertTrue(rel_objects.at(2));

    XCTAssertEqual(rel_objects.at(0).object_id().stable_value(), obj_b1.object_id().stable_value());
    XCTAssertEqual(rel_objects.at(1).object_id().stable_value(), obj_b2.object_id().stable_value());
    XCTAssertEqual(rel_objects.at(2).object_id().stable_value(), obj_b3.object_id().stable_value());
}

- (void)test_setup_migration {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.execute(db::no_cancellation, [self, &manager](auto const &) {
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

        db::select_option option_a{.table = "sample_a", .fields = {db::object_id_field}};
        auto select_result_a = db::select(db, option_a);
        auto &src_obj_id = select_result_a.value().at(0).at(db::object_id_field);

        db::select_option option_b{.table = "sample_b", .fields = {db::object_id_field}};
        auto select_result_b = db::select(db, option_b);
        auto &tgt_obj_id = select_result_b.value().at(0).at(db::object_id_field);

        auto sql = db::insert_sql("rel_sample_a_child", {db::src_obj_id_field, db::tgt_obj_id_field});
        if (!db.execute_update(sql, db::value_vector_t{src_obj_id, tgt_obj_id})) {
            rollback = true;
        }

        db::value const save_id{100};
        if (!db.execute_update(db::update_sql(db::info_table, {db::current_save_id_field, db::last_save_id_field}, ""),
                               db::value_vector_t{save_id, save_id})) {
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
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    manager = nullptr;

    db::model model_0_0_2 = [yas_db_test_utils model_0_0_2];
    manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.execute(db::no_cancellation, [self, &manager](auto const &) {
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

        auto &src_obj_id = sample_a.at(db::object_id_field);
        auto &tgt_obj_id = sample_b.at(db::object_id_field);

        auto &rel = select_rels_result.value().at(0);
        XCTAssertEqual(rel.at(db::src_obj_id_field), src_obj_id);
        XCTAssertEqual(rel.at(db::tgt_obj_id_field), tgt_obj_id);

        XCTAssertTrue(db::index_exists(db, "sample_a_name"));
        XCTAssertTrue(db::index_exists(db, "sample_a_others"));
        XCTAssertTrue(db::index_exists(db, "sample_b_name"));
    });

    exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_insert_objects_by_count {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *exp1 = [self expectationWithDescription:@"insert_1"];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
        XCTAssertEqual(manager.last_save_id(), db::value{0});
    });

    db::object_vector_map_t inserted_objects_1;

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 3}};
                           },
                           [self, exp1, &inserted_objects_1](auto result) {
                               XCTAssertTrue(result);

                               inserted_objects_1 = std::move(result.value());
                               XCTAssertGreaterThan(inserted_objects_1.count("sample_a"), 0);

                               db::object_vector_t const &objects = inserted_objects_1.at("sample_a");
                               XCTAssertEqual(objects.size(), 3);

                               XCTAssertEqual(objects.at(0).object_id().stable_value(), db::value{1});
                               XCTAssertEqual(objects.at(1).object_id().stable_value(), db::value{2});
                               XCTAssertEqual(objects.at(2).object_id().stable_value(), db::value{3});

                               XCTAssertEqual(objects.at(0).save_id(), db::value{1});
                               XCTAssertEqual(objects.at(1).save_id(), db::value{1});
                               XCTAssertEqual(objects.at(2).save_id(), db::value{1});

                               XCTAssertEqual(objects.at(0).action(), db::insert_action_value());
                               XCTAssertEqual(objects.at(1).action(), db::insert_action_value());
                               XCTAssertEqual(objects.at(2).action(), db::insert_action_value());

                               [exp1 fulfill];
                           });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertEqual(inserted_objects_1.size(), 1);
    XCTAssertGreaterThan(inserted_objects_1.count("sample_a"), 0);
    XCTAssertEqual(inserted_objects_1.at("sample_a").size(), 3);

    XCTAssertEqual(manager.current_save_id(), db::value{1});
    XCTAssertEqual(manager.last_save_id(), db::value{1});

    XCTestExpectation *exp2 = [self expectationWithDescription:@"insert_2"];

    db::object_vector_map_t inserted_objects_2;

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self, exp2, &inserted_objects_2](auto result) {
                               XCTAssertTrue(result);

                               inserted_objects_2 = std::move(result.value());
                               db::object_vector_t const &objects = inserted_objects_2.at("sample_a");

                               XCTAssertEqual(objects.size(), 1);

                               XCTAssertEqual(objects.at(0).object_id().stable_value(), db::value{4});
                               XCTAssertEqual(objects.at(0).save_id(), db::value{2});
                               XCTAssertEqual(objects.at(0).action(), db::insert_action_value());

                               [exp2 fulfill];
                           });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertEqual(inserted_objects_2.size(), 1);
    XCTAssertEqual(inserted_objects_2.count("sample_a"), 1);
    XCTAssertEqual(inserted_objects_2.at("sample_a").size(), 1);

    XCTAssertEqual(manager.current_save_id(), db::value{2});
    XCTAssertEqual(manager.last_save_id(), db::value{2});

    auto const object_1 = manager.cached_or_created_object("sample_a", db::make_stable_id(db::value{1}));
    XCTAssertTrue(object_1);
    XCTAssertEqual(object_1.object_id().stable_value(), db::value{1});

    XCTAssertFalse(manager.cached_or_created_object("sample_a", db::make_stable_id(db::value{5})));
}

- (void)test_insert_objects_by_values {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
    });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               db::value_map_t obj1{{"name", db::value{"test_name_1"}}, {"age", db::value{43}}};
                               db::value_map_t obj2{{"name", db::value{"test_name_2"}}, {"age", db::value{67}}};
                               db::value_map_vector_t sample_as{std::move(obj1), std::move(obj2)};
                               return db::value_map_vector_map_t{{"sample_a", std::move(sample_as)}};
                           },
                           [self, &manager](auto result) {
                               XCTAssertTrue(result);

                               auto &objects = result.value();

                               XCTAssertEqual(objects.count("sample_a"), 1);

                               auto &a_objects = objects.at("sample_a");

                               XCTAssertEqual(a_objects.size(), 2);

                               XCTAssertEqual(a_objects.at(0).attribute_value("name"), db::value{"test_name_1"});
                               XCTAssertEqual(a_objects.at(0).attribute_value("age"), db::value{43});
                               XCTAssertEqual(a_objects.at(1).attribute_value("name"), db::value{"test_name_2"});
                               XCTAssertEqual(a_objects.at(1).attribute_value("age"), db::value{67});

                               XCTAssertEqual(manager.current_save_id(), db::value{1});
                           });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_insert_many_entity_objects {
    db::model model_0_0_2 = [yas_db_test_utils model_0_0_2];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 3}, {"sample_b", 5}};
                           },
                           [self](auto result) {
                               db::object_vector_map_t const &objects = result.value();
                               XCTAssertEqual(objects.size(), 2);

                               XCTAssertGreaterThan(objects.count("sample_a"), 0);

                               db::object_vector_t const &a_objects = objects.at("sample_a");
                               XCTAssertEqual(a_objects.size(), 3);

                               XCTAssertGreaterThan(objects.count("sample_b"), 0);

                               db::object_vector_t const &b_objects = objects.at("sample_b");
                               XCTAssertEqual(b_objects.size(), 5);
                           });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_insert_with_delete {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
        XCTAssertEqual(manager.last_save_id(), db::value{0});
    });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self, &manager](auto result) {
                               XCTAssertTrue(result);
                               XCTAssertEqual(manager.current_save_id(), db::value{1});

                               auto &objects = result.value();
                               auto &object = objects.at("sample_a").at(0);
                               XCTAssertEqual(object.save_id(), db::value{1});

                               object.set_attribute_value("name", db::value{"first_name_value"});
                           });

    manager.save(db::no_cancellation, [self, &manager](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{2});
    });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self, &manager](auto result) {
                               XCTAssertTrue(result);
                               XCTAssertEqual(manager.current_save_id(), db::value{3});

                               auto &objects = result.value();
                               auto &object = objects.at("sample_a").at(0);
                               XCTAssertEqual(object.save_id(), db::value{3});

                               object.set_attribute_value("name", db::value{"second_name_value"});
                           });

    manager.save(db::no_cancellation, [self, &manager](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{4});
    });

    manager.revert(db::no_cancellation, []() { return 2; },
                   [self, &manager](auto result) {
                       XCTAssertTrue(result);
                       XCTAssertEqual(manager.current_save_id(), db::value{2});
                   });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self, &manager](auto result) {
                               XCTAssertTrue(result);
                               XCTAssertEqual(manager.current_save_id(), db::value{3});

                               auto &objects = result.value();
                               auto &object = objects.at("sample_a").at(0);
                               XCTAssertEqual(object.save_id(), db::value{3});
                           });

    manager.execute(db::no_cancellation, [self, &manager](task const &) {
        auto &db = manager.database();
        auto result = db::select(db, {.table = "sample_a"});

        auto &object_datas = result.value();
        XCTAssertEqual(object_datas.size(), 3);

        for (auto &object_data : object_datas) {
            XCTAssertNotEqual(object_data.at("name"), db::value{"second_name_value"});
        }
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_fetch_objects {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];

    db::object_vector_map_t objects;

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 3}, {"sample_b", 2}};
                           },
                           [self, exp1, &objects](auto result) {
                               XCTAssertTrue(result);

                               objects = std::move(result.value());

                               XCTAssertGreaterThan(objects.count("sample_a"), 0);
                               auto &a_objects = objects.at("sample_a");
                               XCTAssertEqual(a_objects.size(), 3);
                               XCTAssertEqual(a_objects.at(0).object_id().stable(), 1);
                               XCTAssertEqual(a_objects.at(1).object_id().stable(), 2);
                               XCTAssertEqual(a_objects.at(2).object_id().stable(), 3);
                               XCTAssertEqual(a_objects.at(0).save_id().get<db::integer>(), 1);
                               XCTAssertEqual(a_objects.at(1).save_id().get<db::integer>(), 1);
                               XCTAssertEqual(a_objects.at(2).save_id().get<db::integer>(), 1);
                               XCTAssertEqual(a_objects.at(0).attribute_value("name").get<db::text>(), "default_value");
                               XCTAssertEqual(a_objects.at(1).attribute_value("name").get<db::text>(), "default_value");
                               XCTAssertEqual(a_objects.at(2).attribute_value("name").get<db::text>(), "default_value");

                               XCTAssertGreaterThan(objects.count("sample_b"), 0);
                               auto &b_objects = objects.at("sample_b");
                               XCTAssertEqual(b_objects.size(), 2);
                               XCTAssertEqual(b_objects.at(0).object_id().stable(), 1);
                               XCTAssertEqual(b_objects.at(1).object_id().stable(), 2);
                               XCTAssertEqual(b_objects.at(0).save_id().get<db::integer>(), 1);
                               XCTAssertEqual(b_objects.at(1).save_id().get<db::integer>(), 1);
                               XCTAssertFalse(b_objects.at(0).attribute_value("name"));
                               XCTAssertFalse(b_objects.at(1).attribute_value("name"));

                               [exp1 fulfill];
                           });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{1});
    XCTAssertEqual(manager.last_save_id(), db::value{1});
    objects.at("sample_a").at(1).set_attribute_value("name", db::value{"value_1"});
    objects.at("sample_a").at(1).add_relation_id("child", objects.at("sample_b").at(0).object_id());

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.save(db::no_cancellation, [self, exp2](db::manager_map_result_t result) {
        XCTAssertTrue(result);

        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{2});
    XCTAssertEqual(manager.last_save_id(), db::value{2});

    XCTestExpectation *exp3 = [self expectationWithDescription:@"3"];

    manager.fetch_objects(db::no_cancellation,
                          []() { return db::to_fetch_option(db::select_option{.table = "sample_a"}); },
                          [self, exp3](auto fetch_result) {
                              XCTAssertTrue(fetch_result);

                              auto const &objects = fetch_result.value();
                              XCTAssertGreaterThan(objects.count("sample_a"), 0);
                              auto &a_objects = objects.at("sample_a");
                              XCTAssertEqual(a_objects.size(), 3);
                              XCTAssertEqual(a_objects.at(0).object_id().stable_value(), db::value{1});
                              XCTAssertEqual(a_objects.at(1).object_id().stable_value(), db::value{3});
                              XCTAssertEqual(a_objects.at(2).object_id().stable_value(), db::value{2});
                              XCTAssertEqual(a_objects.at(0).save_id(), db::value{1});
                              XCTAssertEqual(a_objects.at(1).save_id(), db::value{1});
                              XCTAssertEqual(a_objects.at(2).save_id(), db::value{2});
                              XCTAssertEqual(a_objects.at(0).attribute_value("name"), db::value{"default_value"});
                              XCTAssertEqual(a_objects.at(1).attribute_value("name"), db::value{"default_value"});
                              XCTAssertEqual(a_objects.at(2).attribute_value("name"), db::value{"value_1"});

                              XCTAssertEqual(a_objects.at(2).relation_size("child"), 1);
                              XCTAssertEqual(a_objects.at(2).relation_ids("child").size(), 1);
                              XCTAssertEqual(a_objects.at(2).relation_id("child", 0).stable(), 1);

                              [exp3 fulfill];
                          });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    objects.at("sample_a").at(2).set_attribute_value("name", db::value{"value_2"});
    objects.at("sample_a").at(2).remove_all_relations("child");
    objects.at("sample_a").at(2).add_relation_id("child", objects.at("sample_b").at(1).object_id());
    objects.at("sample_a").at(2).add_relation_id("child", objects.at("sample_b").at(0).object_id());

    XCTestExpectation *exp4 = [self expectationWithDescription:@"4"];

    manager.save(db::no_cancellation, [self, exp4](db::manager_map_result_t result) { [exp4 fulfill]; });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{3});
    XCTAssertEqual(manager.last_save_id(), db::value{3});

    manager.fetch_objects(
        db::no_cancellation,
        []() {
            return db::to_fetch_option(db::select_option{.table = "sample_a",
                                                         .where_exprs = db::field_expr("name", "like"),
                                                         .arguments = {{"name", db::value{"value_%"}}},
                                                         .field_orders = {{db::object_id_field, db::order::descending}},
                                                         .limit_range = db::range{0, 3}});
        },
        [self, &objects](auto fetch_result) {
            XCTAssertTrue(fetch_result);

            auto const &objects = fetch_result.value();
            XCTAssertGreaterThan(objects.count("sample_a"), 0);
            auto &a_objects = objects.at("sample_a");
            XCTAssertEqual(a_objects.size(), 2);

            XCTAssertEqual(a_objects.at(0).object_id().stable_value(), db::value{3});
            XCTAssertEqual(a_objects.at(0).save_id(), db::value{3});
            XCTAssertEqual(a_objects.at(0).attribute_value("name"), db::value{"value_2"});

            XCTAssertEqual(a_objects.at(1).object_id().stable_value(), db::value{2});
            XCTAssertEqual(a_objects.at(1).save_id(), db::value{2});
            XCTAssertEqual(a_objects.at(1).attribute_value("name"), db::value{"value_1"});

            XCTAssertEqual(a_objects.at(0).relation_size("child"), 2);
            XCTAssertEqual(a_objects.at(0).relation_ids("child").size(), 2);
            XCTAssertEqual(a_objects.at(0).relation_id("child", 0).stable(), 2);
            XCTAssertEqual(a_objects.at(0).relation_id("child", 1).stable(), 1);
        });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_fetch_const_objects {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) mutable { XCTAssertTrue(result); });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}, {"sample_b", 1}};
                           },
                           [self, &manager](auto result) mutable {
                               XCTAssertTrue(result);
                               auto &objects = result.value();

                               XCTAssertEqual(manager.current_save_id(), db::value{1});
                               XCTAssertEqual(manager.last_save_id(), db::value{1});

                               objects.at("sample_a").at(0).set_attribute_value("name", db::value{"value_0"});

                               auto &object_b = objects.at("sample_b").at(0);
                               objects.at("sample_a").at(0).add_relation_id("child", object_b.object_id());

                               XCTAssertEqual(object_b.object_id().stable_value(), db::value{1});
                           });

    manager.save(db::no_cancellation, [self](db::manager_map_result_t result) { XCTAssertTrue(result); });

    manager.fetch_const_objects(db::no_cancellation,
                                []() { return db::to_fetch_option(db::select_option{.table = "sample_a"}); },
                                [self](db::manager_const_vector_result_t fetch_result) mutable {
                                    XCTAssertTrue(fetch_result);

                                    auto const &objects = fetch_result.value();
                                    XCTAssertGreaterThan(objects.count("sample_a"), 0);
                                    auto &a_objects = objects.at("sample_a");
                                    XCTAssertEqual(a_objects.size(), 1);
                                    XCTAssertEqual(a_objects.at(0).object_id().stable(), 1);
                                    XCTAssertEqual(a_objects.at(0).save_id().get<db::integer>(), 2);
                                    XCTAssertEqual(a_objects.at(0).attribute_value("name"), db::value{"value_0"});

                                    XCTAssertEqual(a_objects.at(0).relation_size("child"), 1);
                                    XCTAssertEqual(a_objects.at(0).relation_ids("child").size(), 1);
                                    XCTAssertEqual(a_objects.at(0).relation_id("child", 0).stable(), 1);
                                });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_fetch_objects_of_relations {
    db::model model_0_0_2 = [yas_db_test_utils model_0_0_2];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}, {"sample_b", 1}, {"sample_c", 1}};
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

                               object_a.add_relation_object("child", object_b);
                               object_a.add_relation_object("friend", object_c);

                               object_b.add_relation_object("parent", object_a);
                               object_c.add_relation_object("friend", object_a);

                               [exp1 fulfill];
                           });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.save(db::no_cancellation, [&manager, self, exp2](db::manager_map_result_t save_result) {
        XCTAssertTrue(save_result);

        db::object_map_map_t const &objects = save_result.value();

        XCTAssertEqual(objects.size(), 3);
        XCTAssertEqual(objects.at("sample_a").size(), 1);
        XCTAssertEqual(objects.at("sample_b").size(), 1);
        XCTAssertEqual(objects.at("sample_c").size(), 1);

        auto const &a_object = objects.at("sample_a").begin()->second;
        auto const &b_object = objects.at("sample_b").begin()->second;
        auto const &c_object = objects.at("sample_c").begin()->second;

        XCTAssertEqual(a_object.relation_size("child"), 1);
        XCTAssertEqual(manager.relation_object_at(a_object, "child", 0), b_object);
        XCTAssertEqual(a_object.relation_id("child", 0).stable(), 1);
        XCTAssertEqual(a_object.relation_size("friend"), 1);
        XCTAssertEqual(manager.relation_object_at(a_object, "friend", 0), c_object);
        XCTAssertEqual(a_object.relation_id("friend", 0).stable(), 1);

        XCTAssertEqual(b_object.relation_size("parent"), 1);
        XCTAssertEqual(manager.relation_object_at(b_object, "parent", 0), a_object);

        XCTAssertEqual(c_object.relation_size("friend"), 1);
        XCTAssertEqual(manager.relation_object_at(c_object, "friend", 0), a_object);

        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertFalse(manager.cached_or_created_object("sample_a", db::make_stable_id(db::value{1})));
    XCTAssertFalse(manager.cached_or_created_object("sample_b", db::make_stable_id(db::value{1})));
    XCTAssertFalse(manager.cached_or_created_object("sample_c", db::make_stable_id(db::value{1})));

    XCTestExpectation *exp3 = [self expectationWithDescription:@"3"];

    auto object_a = db::null_object();

    manager.fetch_objects(db::no_cancellation,
                          []() { return db::to_fetch_option(db::select_option{.table = "sample_a"}); },
                          [self, exp3, &object_a, &manager](auto const &fetch_result) {
                              XCTAssertTrue(fetch_result);

                              auto const &objects = fetch_result.value();

                              XCTAssertEqual(objects.size(), 1);

                              object_a = objects.at("sample_a").at(0);
                              XCTAssertEqual(objects.at("sample_a").at(0).relation_size("child"), 1);
                              XCTAssertFalse(manager.relation_object_at(objects.at("sample_a").at(0), "child", 0));
                              XCTAssertEqual(objects.at("sample_a").at(0).relation_size("friend"), 1);
                              XCTAssertFalse(manager.relation_object_at(objects.at("sample_a").at(0), "friend", 0));

                              [exp3 fulfill];
                          });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    manager.fetch_objects(
        db::no_cancellation, db::to_ids_preparation([object_a]() {
            return db::object_vector_map_t{std::make_pair("sample_a", db::object_vector_t{object_a})};
        }),
        [self, object_a, &manager](auto const &fetch_result) {
            XCTAssertTrue(fetch_result);

            auto const &objects = fetch_result.value();

            XCTAssertEqual(objects.size(), 2);
            XCTAssertEqual(objects.count("sample_b"), 1);
            XCTAssertEqual(objects.count("sample_c"), 1);

            XCTAssertEqual(objects.at("sample_b").size(), 1);
            XCTAssertEqual(manager.relation_object_at(object_a, "child", 0), objects.at("sample_b").at(1));
            XCTAssertEqual(manager.relation_object_at(objects.at("sample_b").at(1), "parent", 0), object_a);

            XCTAssertEqual(objects.at("sample_c").size(), 1);
            XCTAssertEqual(manager.relation_object_at(object_a, "friend", 0), objects.at("sample_c").at(1));
            XCTAssertEqual(manager.relation_object_at(objects.at("sample_c").at(1), "friend", 0), object_a);
        });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_fetch_const_objects_by_ids {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) mutable { XCTAssertTrue(result); });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 3}};
                           },
                           [self, &manager](auto result) mutable {
                               XCTAssertTrue(result);
                               auto &objects = result.value();

                               XCTAssertEqual(manager.current_save_id(), db::value{1});
                               XCTAssertEqual(manager.last_save_id(), db::value{1});

                               objects.at("sample_a").at(0).set_attribute_value("name", db::value{"value_1"});
                               objects.at("sample_a").at(1).set_attribute_value("name", db::value{"value_2"});
                               objects.at("sample_a").at(2).set_attribute_value("name", db::value{"value_3"});

                               XCTAssertEqual(objects.at("sample_a").at(0).object_id().stable_value(), db::value{1});
                               XCTAssertEqual(objects.at("sample_a").at(1).object_id().stable_value(), db::value{2});
                               XCTAssertEqual(objects.at("sample_a").at(2).object_id().stable_value(), db::value{3});
                           });

    manager.save(db::no_cancellation, [self](db::manager_map_result_t result) { XCTAssertTrue(result); });

    manager.fetch_const_objects(db::no_cancellation,
                                []() {
                                    return db::integer_set_map_t{{"sample_a", {2}}};
                                },
                                [self](auto fetch_result) mutable {
                                    XCTAssertTrue(fetch_result);

                                    auto const &objects = fetch_result.value();
                                    XCTAssertEqual(objects.count("sample_a"), 1);
                                    auto &a_objects = objects.at("sample_a");
                                    XCTAssertEqual(a_objects.size(), 1);
                                    XCTAssertEqual(a_objects.at(2).object_id().stable_value(), db::value{2});
                                    XCTAssertEqual(a_objects.at(2).attribute_value("name"), db::value{"value_2"});
                                });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_fetch_relation_objects {
    db::model model_0_0_2 = [yas_db_test_utils model_0_0_2];
    db::manager manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    XCTestExpectation *setupExp = [self expectationWithDescription:@"setup"];

    manager.setup([setupExp](db::manager_result_t) { [setupExp fulfill]; });

    [self waitForExpectations:@[setupExp] timeout:10.0];

    db::object obj_a_1 = manager.create_object("sample_a");
    db::object obj_a_2 = manager.create_object("sample_a");
    db::object obj_b_1 = manager.create_object("sample_b");
    db::object obj_b_2 = manager.create_object("sample_b");
    db::object obj_b_3 = manager.create_object("sample_b");
    db::object obj_b_4 = manager.create_object("sample_b");
    db::object obj_c_1 = manager.create_object("sample_c");

    obj_a_1.add_relation_object("child", obj_b_1);
    obj_a_1.add_relation_object("child", obj_b_2);
    obj_a_1.add_relation_object("child", obj_b_3);
    obj_a_2.add_relation_object("child", obj_b_3);
    obj_a_2.add_relation_object("child", obj_b_4);
    obj_a_1.add_relation_object("friend", obj_c_1);

    XCTestExpectation *saveExp = [self expectationWithDescription:@"save"];

    db::object_map_map_t saved_objects;

    manager.save(db::no_cancellation, [saveExp, &saved_objects](db::manager_map_result_t result) {
        saved_objects = std::move(result.value());

        [saveExp fulfill];
    });

    [self waitForExpectations:@[saveExp] timeout:10.0];

    db::object_vector_t objects{obj_a_1, obj_a_2};

    db::object_map_map_t fetched_objects;

    XCTestExpectation *fetchExp = [self expectationWithDescription:@"fetch"];

    manager.fetch_objects(db::no_cancellation, db::to_ids_preparation([objects]() { return objects; }),
                          [&fetched_objects, fetchExp](db::manager_map_result_t result) {
                              fetched_objects = std::move(result.value());

                              [fetchExp fulfill];
                          });

    [self waitForExpectations:@[fetchExp] timeout:10.0];

    XCTAssertEqual(fetched_objects.size(), 2);

    db::object_map_t const &fetched_b_objects = fetched_objects.at("sample_b");
    XCTAssertEqual(fetched_b_objects.size(), 4);
    XCTAssertEqual(fetched_b_objects.count(obj_b_1.object_id().stable()), 1);
    XCTAssertEqual(fetched_b_objects.count(obj_b_2.object_id().stable()), 1);
    XCTAssertEqual(fetched_b_objects.count(obj_b_3.object_id().stable()), 1);
    XCTAssertEqual(fetched_b_objects.count(obj_b_4.object_id().stable()), 1);

    db::object_map_t const &fetched_c_objects = fetched_objects.at("sample_c");
    XCTAssertEqual(fetched_c_objects.size(), 1);
    XCTAssertEqual(fetched_c_objects.count(obj_c_1.object_id().stable()), 1);
}

- (void)test_fetch_const_relation_objects {
    db::model model_0_0_2 = [yas_db_test_utils model_0_0_2];
    db::manager manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    XCTestExpectation *setupExp = [self expectationWithDescription:@"setup"];

    manager.setup([setupExp](db::manager_result_t) { [setupExp fulfill]; });

    [self waitForExpectations:@[setupExp] timeout:10.0];

    db::object obj_a_1 = manager.create_object("sample_a");
    db::object obj_a_2 = manager.create_object("sample_a");
    db::object obj_b_1 = manager.create_object("sample_b");
    db::object obj_b_2 = manager.create_object("sample_b");
    db::object obj_b_3 = manager.create_object("sample_b");
    db::object obj_b_4 = manager.create_object("sample_b");
    db::object obj_c_1 = manager.create_object("sample_c");

    obj_a_1.add_relation_object("child", obj_b_1);
    obj_a_1.add_relation_object("child", obj_b_2);
    obj_a_1.add_relation_object("child", obj_b_3);
    obj_a_2.add_relation_object("child", obj_b_3);
    obj_a_2.add_relation_object("child", obj_b_4);
    obj_a_1.add_relation_object("friend", obj_c_1);

    XCTestExpectation *saveExp = [self expectationWithDescription:@"save"];

    db::object_map_map_t saved_objects;

    manager.save(db::no_cancellation, [saveExp, &saved_objects](db::manager_map_result_t result) {
        saved_objects = std::move(result.value());

        [saveExp fulfill];
    });

    [self waitForExpectations:@[saveExp] timeout:10.0];

    db::object_vector_t objects{obj_a_1, obj_a_2};

    db::const_object_map_map_t fetched_objects;

    XCTestExpectation *fetchExp = [self expectationWithDescription:@"fetch"];

    manager.fetch_const_objects(db::no_cancellation, db::to_ids_preparation([objects]() { return objects; }),
                                [&fetched_objects, fetchExp](db::manager_const_map_result_t result) {
                                    fetched_objects = std::move(result.value());

                                    [fetchExp fulfill];
                                });

    [self waitForExpectations:@[fetchExp] timeout:10.0];

    XCTAssertEqual(fetched_objects.size(), 2);

    db::const_object_map_t const &fetched_b_objects = fetched_objects.at("sample_b");
    XCTAssertEqual(fetched_b_objects.size(), 4);
    XCTAssertEqual(fetched_b_objects.count(obj_b_1.object_id().stable()), 1);
    XCTAssertEqual(fetched_b_objects.count(obj_b_2.object_id().stable()), 1);
    XCTAssertEqual(fetched_b_objects.count(obj_b_3.object_id().stable()), 1);
    XCTAssertEqual(fetched_b_objects.count(obj_b_4.object_id().stable()), 1);

    db::const_object_map_t const &fetched_c_objects = fetched_objects.at("sample_c");
    XCTAssertEqual(fetched_c_objects.size(), 1);
    XCTAssertEqual(fetched_c_objects.count(obj_c_1.object_id().stable()), 1);
}

- (void)test_save_objects {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
        XCTAssertEqual(manager.last_save_id(), db::value{0});
    });

    std::unordered_map<db::integer::type, db::object> main_objects;

    XCTestExpectation *exp1 = [self expectationWithDescription:@"1"];

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self, &main_objects, exp1](auto result) {
                               db::object_vector_map_t const &objects = result.value();
                               db::object_vector_t const &a_objects = objects.at("sample_a");
                               for (auto const &obj : a_objects) {
                                   main_objects.insert(std::make_pair(obj.object_id().stable(), obj));
                               }

                               XCTAssertEqual(main_objects.size(), 1);

                               auto const &obj = a_objects.at(0);
                               XCTAssertEqual(obj.save_id(), db::value{1});
                               XCTAssertEqual(obj.attribute_value("name"), db::value{"default_value"});
                               XCTAssertEqual(obj.status(), db::object_status::saved);
                               XCTAssertEqual(obj.action(), db::insert_action_value());

                               [exp1 fulfill];
                           });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{1});
    XCTAssertEqual(manager.last_save_id(), db::value{1});

    XCTestExpectation *exp2 = [self expectationWithDescription:@"2"];

    manager.save(db::no_cancellation, [self, exp2](db::manager_map_result_t result) {
        auto const &objects = result.value();
        XCTAssertEqual(objects.size(), 0);

        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertEqual(main_objects.size(), 1);
    auto &object = main_objects.at(1);
    object.set_attribute_value("name", db::value{"new_value"});
    object.set_attribute_value("age", db::value{77});
    object.add_relation_id("child", db::make_stable_id(db::value{100}));
    object.add_relation_id("child", db::make_stable_id(db::value{200}));
    XCTAssertEqual(object.status(), db::object_status::changed);

    XCTestExpectation *exp3 = [self expectationWithDescription:@"3"];

    manager.save(db::no_cancellation, [self, exp3](db::manager_map_result_t result) {
        XCTAssertTrue(result);

        auto const &objects = result.value();
        XCTAssertGreaterThan(objects.count("sample_a"), 0);

        auto const &a_objects = objects.at("sample_a");
        XCTAssertEqual(a_objects.size(), 1);

        auto const &obj = a_objects.begin()->second;
        XCTAssertEqual(obj.save_id(), db::value{2});
        XCTAssertEqual(obj.attribute_value("name"), db::value{"new_value"});
        XCTAssertEqual(obj.attribute_value("age"), db::value{77});
        XCTAssertEqual(obj.status(), db::object_status::saved);
        XCTAssertEqual(obj.action(), db::update_action_value());
        XCTAssertEqual(obj.relation_size("child"), 2);
        XCTAssertEqual(obj.relation_ids("child").size(), 2);
        XCTAssertEqual(obj.relation_id("child", 0).stable(), 100);
        XCTAssertEqual(obj.relation_id("child", 1).stable(), 200);
    });

    manager.execute(db::no_cancellation, [self, exp3, &manager](task const &) {
        auto &db = manager.database();

        auto value_result = db::select(db, db::select_option{.table = "sample_a"});
        auto const &selected_values = value_result.value();

        XCTAssertEqual(selected_values.size(), 2);
        XCTAssertEqual(selected_values.at(0).at("name"), db::value{"default_value"});
        XCTAssertEqual(selected_values.at(0).at("age"), db::value{10});
        XCTAssertEqual(selected_values.at(0).at(db::save_id_field), db::value{1});
        XCTAssertEqual(selected_values.at(0).at(db::action_field), db::insert_action_value());
        XCTAssertEqual(selected_values.at(1).at("name"), db::value{"new_value"});
        XCTAssertEqual(selected_values.at(1).at("age"), db::value{77});
        XCTAssertEqual(selected_values.at(1).at(db::save_id_field), db::value{2});
        XCTAssertEqual(selected_values.at(1).at(db::action_field), db::update_action_value());

        auto relation_result =
            db::select(db, db::select_option{.table = manager.model().relation("sample_a", "child").table});
        auto const &selected_relations = relation_result.value();

        XCTAssertEqual(selected_relations.size(), 2);
        XCTAssertEqual(selected_relations.at(0).at(db::tgt_obj_id_field), db::value{100});
        XCTAssertEqual(selected_relations.at(1).at(db::tgt_obj_id_field), db::value{200});

        [exp3 fulfill];
    });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{2});
    XCTAssertEqual(manager.last_save_id(), db::value{2});
    XCTAssertEqual(object.attribute_value("name"), db::value{"new_value"});
    XCTAssertEqual(object.attribute_value("age"), db::value{77});
    XCTAssertEqual(object.save_id(), db::value{2});
    XCTAssertEqual(object.status(), db::object_status::saved);
    XCTAssertEqual(object.relation_size("child"), 2);
    XCTAssertEqual(object.relation_ids("child").size(), 2);
    XCTAssertEqual(object.relation_id("child", 0).stable(), 100);
    XCTAssertEqual(object.relation_id("child", 1).stable(), 200);

    object.remove();

    XCTAssertEqual(object.status(), db::object_status::changed);

    XCTestExpectation *exp4 = [self expectationWithDescription:@"4"];

    manager.save(db::no_cancellation, [self, exp4](db::manager_map_result_t save_result) {
        XCTAssertTrue(save_result);

        auto const &objects = save_result.value();
        XCTAssertGreaterThan(objects.count("sample_a"), 0);

        auto const &a_objects = objects.at("sample_a");
        XCTAssertEqual(a_objects.size(), 1);

        auto const &obj = a_objects.begin()->second;
        XCTAssertEqual(obj.save_id(), db::value{3});
        XCTAssertEqual(obj.attribute_value("name"), db::null_value());
        XCTAssertEqual(obj.attribute_value("age"), db::value{10});
        XCTAssertEqual(obj.relation_size("child"), 0);
        XCTAssertEqual(obj.relation_ids("child").size(), 0);
        XCTAssertTrue(obj.is_removed());
        XCTAssertEqual(obj.status(), db::object_status::saved);
        XCTAssertEqual(obj.action(), db::remove_action_value());

        [exp4 fulfill];
    });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{3});
    XCTAssertEqual(manager.last_save_id(), db::value{3});

    manager.save(db::no_cancellation, [self](db::manager_map_result_t result) {
        XCTAssertTrue(result);

        auto const &objects = result.value();
        XCTAssertEqual(objects.size(), 0);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertEqual(manager.current_save_id(), db::value{3});
    XCTAssertEqual(manager.last_save_id(), db::value{3});
}

- (void)test_save_with_delete {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
        XCTAssertEqual(manager.last_save_id(), db::value{0});
    });

    db::object_vector_t a_objects;

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 2}};
                           },
                           [self, &manager, &a_objects](auto result) {
                               XCTAssertTrue(result);
                               XCTAssertEqual(manager.current_save_id(), db::value{1});

                               auto &objects = result.value();
                               XCTAssertEqual(objects.count("sample_a"), 1);

                               a_objects = std::move(objects.at("sample_a"));
                               XCTAssertEqual(a_objects.size(), 2);

                               auto &object = a_objects.at(0);
                               object.set_attribute_value("name", db::value{"name_value_0"});
                           });

    manager.save(db::no_cancellation, [self, &manager, &a_objects](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{2});
        XCTAssertEqual(a_objects.at(0).save_id(), db::value{2});

        auto &object = a_objects.at(1);
        object.set_attribute_value("name", db::value{"name_value_1_a"});
    });

    manager.save(db::no_cancellation, [self, &manager, &a_objects](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{3});
        XCTAssertEqual(a_objects.at(1).save_id(), db::value{3});
    });

    manager.revert(db::no_cancellation, []() { return 2; },
                   [self, &manager, &a_objects](auto result) {
                       XCTAssertTrue(result);
                       XCTAssertEqual(manager.current_save_id(), db::value{2});

                       auto &object = a_objects.at(1);
                       object.set_attribute_value("name", db::value{"name_value_1_b"});
                   });

    manager.save(db::no_cancellation, [self, &manager, &a_objects](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{3});
        XCTAssertEqual(a_objects.at(1).save_id(), db::value{3});
    });

    manager.execute(db::no_cancellation, [self, &manager](task const &) {
        auto &db = manager.database();
        auto result = db::select(db, {.table = "sample_a"});

        auto &object_datas = result.value();
        XCTAssertEqual(object_datas.size(), 4);

        for (auto &object_data : object_datas) {
            XCTAssertNotEqual(object_data.at("name"), db::value{"name_value_1_a"});
        }
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_revert_objects {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    auto a_object = db::null_object();

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{0});
        XCTAssertEqual(manager.last_save_id(), db::value{0});
    });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self, &a_object](auto result) mutable {
                               a_object = result.value().at("sample_a").at(0);

                               XCTAssertEqual(a_object.save_id(), db::value{1});

                               a_object.set_attribute_value("name", db::value{"value_2"});
                           });

    manager.save(db::no_cancellation, [self, &a_object](db::manager_map_result_t result) mutable {
        XCTAssertTrue(result);

        XCTAssertEqual(a_object.save_id(), db::value{2});

        a_object.remove();
    });

    manager.save(db::no_cancellation, [self, &a_object](db::manager_map_result_t result) mutable {
        XCTAssertTrue(result);

        XCTAssertEqual(a_object.save_id(), db::value{3});
        XCTAssertTrue(a_object.is_removed());
    });

    manager.revert(db::no_cancellation, []() { return 2; },
                   [self, &a_object](auto result) mutable {
                       XCTAssertTrue(result);

                       XCTAssertEqual(a_object.save_id(), db::value{2});
                       XCTAssertEqual(a_object.attribute_value("name"), db::value{"value_2"});
                       XCTAssertFalse(a_object.is_removed());
                   });

    manager.revert(db::no_cancellation, []() { return 1; },
                   [self, &a_object](auto result) mutable {
                       XCTAssertTrue(result);

                       XCTAssertEqual(a_object.save_id(), db::value{1});
                       XCTAssertEqual(a_object.attribute_value("name"), db::value{"default_value"});

                       a_object.set_attribute_value("name", db::value{"value_b"});
                   });

    manager.save(db::no_cancellation, [self](db::manager_map_result_t result) mutable { XCTAssertTrue(result); });

    manager.execute(db::no_cancellation, [self, &manager](task const &) mutable {
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

    manager.revert(db::no_cancellation, []() { return 0; },
                   [self, &a_object](auto result) mutable {
                       XCTAssertTrue(result);

                       XCTAssertEqual(a_object.status(), db::object_status::invalid);
                       XCTAssertFalse(a_object.save_id());
                       XCTAssertFalse(a_object.action());
                       XCTAssertFalse(a_object.attribute_value("name"));
                   });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_restore_reverted_db {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    if (auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)]) {
        db::object_vector_map_t objects;

        manager.setup([self, &manager](auto result) mutable {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{0});
            XCTAssertEqual(manager.last_save_id(), db::value{0});
        });

        manager.insert_objects(db::no_cancellation,
                               []() {
                                   return db::entity_count_map_t{{"sample_a", 1}, {"sample_b", 2}};
                               },
                               [self, &manager, &objects](auto result) mutable {
                                   XCTAssertTrue(result);
                                   XCTAssertEqual(manager.current_save_id(), db::value{1});
                                   XCTAssertEqual(manager.last_save_id(), db::value{1});

                                   objects = std::move(result.value());

                                   objects.at("sample_a").at(0).set_attribute_value("name", db::value{"name_value_1"});
                                   objects.at("sample_b").at(0).set_attribute_value("name", db::value{"name_value_2"});
                                   objects.at("sample_b").at(1).set_attribute_value("name", db::value{"name_value_3"});
                               });

        manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) mutable {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{2});
            XCTAssertEqual(manager.last_save_id(), db::value{2});

            objects.at("sample_a").at(0).set_attribute_value("name", db::value{"name_value_4"});
            objects.at("sample_b").at(0).set_attribute_value("name", db::value{"name_value_5"});
            objects.at("sample_a").at(0).set_relation_objects("child", {objects.at("sample_b").at(0)});
            XCTAssertEqual(objects.at("sample_b").at(0).object_id().stable_value(), db::value{1});
        });

        manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) mutable {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{3});
            XCTAssertEqual(manager.last_save_id(), db::value{3});

            objects.at("sample_a").at(0).set_attribute_value("name", db::value{"name_value_6"});
            objects.at("sample_b").at(1).set_attribute_value("name", db::value{"name_value_7"});
            objects.at("sample_a").at(0).set_relation_objects("child", {objects.at("sample_b").at(1)});
        });

        manager.save(db::no_cancellation, [self, &manager](db::manager_map_result_t result) mutable {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{4});
            XCTAssertEqual(manager.last_save_id(), db::value{4});
        });

        manager.revert(db::no_cancellation, []() { return 3; },
                       [self, &manager](auto result) mutable {
                           XCTAssertTrue(result);
                           XCTAssertEqual(manager.current_save_id(), db::value{3});
                           XCTAssertEqual(manager.last_save_id(), db::value{4});
                       });

        XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
        manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
        [self waitForExpectationsWithTimeout:10.0 handler:nil];
    } else {
        XCTAssert(0);
    }

    if (auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)]) {
        db::object_vector_map_t objects{};

        manager.setup([self, &manager](auto result) mutable {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{3});
            XCTAssertEqual(manager.last_save_id(), db::value{4});
        });

        manager.fetch_objects(
            db::no_cancellation, []() { return db::to_fetch_option(db::select_option{.table = "sample_a"}); },
            [self, &objects](auto result) mutable {
                XCTAssertTrue(result);

                objects = std::move(result.value());

                XCTAssertEqual(objects.count("sample_a"), 1);
                XCTAssertEqual(objects.at("sample_a").at(0).attribute_value("name"), db::value{"name_value_4"});
                XCTAssertEqual(objects.at("sample_a").at(0).relation_size("child"), 1);
            });

        manager.fetch_objects(
            db::no_cancellation, db::to_ids_preparation([&objects]() { return objects; }),
            [self, &objects, &manager](auto result) mutable {
                XCTAssertTrue(result);

                db::object_map_map_t &rel_objects = result.value();

                XCTAssertEqual(rel_objects.count("sample_b"), 1);
                XCTAssertEqual(rel_objects.at("sample_b").at(1).attribute_value("name"), db::value{"name_value_5"});

                auto sample_bs =
                    to_vector<db::object>(rel_objects.at("sample_b"), [](auto &pair) { return pair.second; });
                objects.emplace("sample_b", std::move(sample_bs));

                XCTAssertEqual(
                    manager.relation_object_at(objects.at("sample_a").at(0), "child", 0).attribute_value("name"),
                    db::value{"name_value_5"});
            });

        XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
        manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
        [self waitForExpectationsWithTimeout:10.0 handler:nil];
    } else {
        XCTAssert(0);
    }
}

- (void)test_suspend_count {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1) priority_count:2];

    XCTAssertFalse(manager.is_suspended());

    manager.suspend();

    XCTAssertTrue(manager.is_suspended());

    manager.suspend();

    XCTAssertTrue(manager.is_suspended());

    manager.resume();

    XCTAssertTrue(manager.is_suspended());

    manager.resume();

    XCTAssertFalse(manager.is_suspended());

    XCTAssertThrows(manager.resume());
}

- (void)test_clear {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    auto object = db::null_object();

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self, &object](auto result) {
                               XCTAssertTrue(result);
                               auto &objects = result.value();
                               auto &a_objects = objects.at("sample_a");

                               object = std::move(a_objects.at(0));

                               object.set_attribute_value("name", db::value{"test_clear_value"});
                           });

    manager.save(db::no_cancellation, [self, &manager, &object](db::manager_map_result_t result) {
        XCTAssertTrue(result);

        XCTAssertEqual(object.status(), db::object_status::saved);
        XCTAssertEqual(object.object_id().stable_value(), db::value{1});
        XCTAssertEqual(object.attribute_value("name"), db::value{"test_clear_value"});

        XCTAssertTrue(manager.cached_or_created_object("sample_a", db::make_stable_id(db::value{1})));
    });

    manager.clear(db::no_cancellation, [self, &manager, &object](auto result) {
        XCTAssertTrue(result);

        XCTAssertEqual(object.status(), db::object_status::invalid);
        XCTAssertFalse(object.attribute_value("name"));

        XCTAssertFalse(manager.cached_or_created_object("sample_a", db::make_stable_id(db::value{1})));
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_cancel_clear {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    auto object = db::null_object();

    XCTestExpectation *setupExp = [self expectationWithDescription:@"setup"];

    bool is_setup_succeeded = false;

    manager.setup([self, &manager, &setupExp, &is_setup_succeeded](auto result) {
        if (result) {
            is_setup_succeeded = true;
        }

        [setupExp fulfill];
    });

    [self waitForExpectations:@[setupExp] timeout:10.0];

    XCTAssertTrue(is_setup_succeeded);

    bool is_called = false;

    manager.clear([]() { return true; },
                  [self, &manager, &object, &is_called](auto result) mutable { is_called = true; });

    XCTestExpectation *exp = [self expectationWithDescription:@"end"];
    manager.execute(db::no_cancellation, [&exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertFalse(is_called);
}

- (void)test_purge {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    db::object_vector_map_t objects;

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}, {"sample_b", 2}};
                           },
                           [self, &manager, &objects](auto result) {
                               XCTAssertTrue(result);
                               XCTAssertEqual(manager.current_save_id(), db::value{1});

                               objects = result.value();
                               auto &obj_a = objects.at("sample_a").at(0);
                               auto &obj_b0 = objects.at("sample_b").at(0);
                               auto &obj_b1 = objects.at("sample_b").at(1);

                               obj_a.set_attribute_value("name", db::value{"obj_a_2"});
                               obj_b0.set_attribute_value("name", db::value{"obj_b0_2"});
                               obj_b1.set_attribute_value("name", db::value{"obj_b1_2"});

                               obj_a.set_relation_objects("child", {obj_b0});
                           });

    manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{2});

        auto &obj_a = objects.at("sample_a").at(0);
        auto &obj_b0 = objects.at("sample_b").at(0);
        auto &obj_b1 = objects.at("sample_b").at(1);

        obj_a.set_attribute_value("name", db::value{"obj_a_3"});
        obj_b0.set_attribute_value("name", db::value{"obj_b0_3"});
        obj_b1.set_attribute_value("name", db::value{"obj_b1_3"});

        obj_a.set_relation_objects("child", {obj_b0, obj_b1});
    });

    manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{3});

        auto &obj_a = objects.at("sample_a").at(0);
        auto &obj_b0 = objects.at("sample_b").at(0);
        auto &obj_b1 = objects.at("sample_b").at(1);

        obj_a.set_attribute_value("name", db::value{"obj_a_4"});
        obj_b0.set_attribute_value("name", db::value{"obj_b0_4"});
        obj_b1.set_attribute_value("name", db::value{"obj_b1_4"});

        obj_a.set_relation_objects("child", {obj_b1});
    });

    manager.save(db::no_cancellation, [self, &manager](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{4});
    });

    manager.revert(db::no_cancellation, []() { return 3; },
                   [self, &manager](auto result) {
                       XCTAssertTrue(result);
                       XCTAssertEqual(manager.current_save_id(), db::value{3});
                       XCTAssertEqual(manager.last_save_id(), db::value{4});
                   });

    manager.purge(db::no_cancellation, [self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{1});
        XCTAssertEqual(manager.last_save_id(), db::value{1});

        auto &obj_a = objects.at("sample_a").at(0);
        auto &obj_b0 = objects.at("sample_b").at(0);
        auto &obj_b1 = objects.at("sample_b").at(1);

        XCTAssertEqual(obj_a.attribute_value("name"), db::value{"obj_a_3"});
        XCTAssertEqual(obj_b0.attribute_value("name"), db::value{"obj_b0_3"});
        XCTAssertEqual(obj_b1.attribute_value("name"), db::value{"obj_b1_3"});

        XCTAssertEqual(obj_a.save_id(), db::value{1});
        XCTAssertEqual(obj_b0.save_id(), db::value{1});
        XCTAssertEqual(obj_b1.save_id(), db::value{1});
    });

    manager.execute(db::no_cancellation, [self, &manager](auto const &) {
        auto &db = manager.database();
        auto const &rel_table_name = manager.model().entities().at("sample_a").relations.at("child").table;

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
            b_objects, [](db::value_map_t &obj) { return obj.at(db::object_id_field).get<db::integer>(); });

        XCTAssertEqual(b_object_map.at(1).at("name"), db::value{"obj_b0_3"});
        XCTAssertEqual(b_object_map.at(1).at(db::save_id_field), db::value{1});
        XCTAssertEqual(b_object_map.at(2).at("name"), db::value{"obj_b1_3"});
        XCTAssertEqual(b_object_map.at(2).at(db::save_id_field), db::value{1});

        auto select_rel_result = db::select(db, db::select_option{.table = rel_table_name});
        XCTAssertTrue(select_rel_result);

        auto &rel_objects = select_rel_result.value();
        XCTAssertEqual(rel_objects.size(), 2);

        XCTAssertEqual(rel_objects.at(0).at(db::src_pk_id_field), db::value{3});
        XCTAssertEqual(rel_objects.at(0).at(db::src_obj_id_field), db::value{1});
        XCTAssertEqual(rel_objects.at(0).at(db::tgt_obj_id_field), db::value{1});
        XCTAssertEqual(rel_objects.at(0).at(db::save_id_field), db::value{1});
        XCTAssertEqual(rel_objects.at(1).at(db::src_pk_id_field), db::value{3});
        XCTAssertEqual(rel_objects.at(1).at(db::src_obj_id_field), db::value{1});
        XCTAssertEqual(rel_objects.at(1).at(db::tgt_obj_id_field), db::value{2});
        XCTAssertEqual(rel_objects.at(1).at(db::save_id_field), db::value{1});
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_cancel_purge {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    auto object = db::null_object();

    XCTestExpectation *setupExp = [self expectationWithDescription:@"setup"];

    bool is_setup_succeeded = false;

    manager.setup([self, &manager, &setupExp, &is_setup_succeeded](auto result) {
        if (result) {
            is_setup_succeeded = true;
        }

        [setupExp fulfill];
    });

    [self waitForExpectations:@[setupExp] timeout:10.0];

    XCTAssertTrue(is_setup_succeeded);

    bool is_called = false;

    manager.purge([]() { return true; }, [&is_called](auto result) { is_called = true; });

    XCTestExpectation *exp = [self expectationWithDescription:@"end"];
    manager.execute(db::no_cancellation, [&exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    XCTAssertFalse(is_called);
}

- (void)test_has_inserted {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);

        XCTAssertFalse(manager.has_created_objects());

        manager.create_object("sample_a");

        XCTAssertTrue(manager.has_created_objects());
    });

    manager.save(db::no_cancellation, [self, &manager](db::manager_map_result_t result) {
        XCTAssertTrue(result);

        XCTAssertFalse(manager.has_created_objects());
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_has_changed {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self, &manager](auto result) {
                               XCTAssertFalse(manager.has_changed_objects());

                               auto &obj = result.value().at("sample_a").at(0);
                               obj.set_attribute_value("name", db::value{"a"});

                               XCTAssertTrue(manager.has_changed_objects());
                           });

    manager.save(db::no_cancellation,
                 [self, &manager](db::manager_map_result_t result) { XCTAssertFalse(manager.has_changed_objects()); });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_created_object_count {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) {
        XCTAssertTrue(result);

        XCTAssertEqual(manager.created_object_count("sample_a"), 0);

        manager.create_object("sample_a");

        XCTAssertEqual(manager.created_object_count("sample_a"), 1);

        manager.create_object("sample_a");

        XCTAssertEqual(manager.created_object_count("sample_a"), 2);
    });

    manager.save(db::no_cancellation, [self, &manager](db::manager_map_result_t result) {
        XCTAssertTrue(result);

        XCTAssertEqual(manager.created_object_count("sample_a"), 0);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_changed_object_count {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 2}};
                           },
                           [self, &manager](auto result) {
                               XCTAssertEqual(manager.changed_object_count("sample_a"), 0);

                               auto &obj = result.value().at("sample_a").at(0);
                               obj.set_attribute_value("name", db::value{"a"});

                               XCTAssertEqual(manager.changed_object_count("sample_a"), 1);

                               obj = result.value().at("sample_a").at(1);
                               obj.set_attribute_value("name", db::value{"b"});

                               XCTAssertEqual(manager.changed_object_count("sample_a"), 2);
                           });

    manager.save(db::no_cancellation, [self, &manager](db::manager_map_result_t result) {
        XCTAssertTrue(result);

        XCTAssertEqual(manager.changed_object_count("sample_a"), 0);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_is_temporary {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    XCTestExpectation *setupExp = [self expectationWithDescription:@"setup"];

    manager.setup([self, setupExp](auto result) {
        XCTAssertTrue(result);

        [setupExp fulfill];
    });

    [self waitForExpectations:@[setupExp] timeout:10.0];

    auto object = manager.create_object("sample_a");

    XCTAssertTrue(object.is_temporary());

    XCTestExpectation *saveExp = [self expectationWithDescription:@"save"];

    manager.save(db::no_cancellation, [saveExp](db::manager_map_result_t result) { [saveExp fulfill]; });

    [self waitForExpectations:@[saveExp] timeout:10.0];

    XCTAssertFalse(object.is_temporary());
}

- (void)test_reset {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    db::object_vector_map_t objects;

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}, {"sample_b", 2}};
                           },
                           [self, &manager, &objects](auto result) {
                               XCTAssertTrue(result);

                               objects = std::move(result.value());
                               auto &obj_a = objects.at("sample_a").at(0);
                               auto &obj_b0 = objects.at("sample_b").at(0);
                               auto &obj_b1 = objects.at("sample_b").at(1);

                               obj_a.set_attribute_value("name", db::value{"a_test_1"});
                               obj_b0.set_attribute_value("name", db::value{"b0_test_1"});
                               obj_b1.set_attribute_value("name", db::value{"b1_test_1"});
                               obj_a.set_relation_objects("child", {obj_b0});
                           });

    manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        auto &obj_a = objects.at("sample_a").at(0);
        auto &obj_b0 = objects.at("sample_b").at(0);
        auto &obj_b1 = objects.at("sample_b").at(1);

        obj_a.set_attribute_value("name", db::value{"a_test_2"});
        obj_b0.set_attribute_value("name", db::value{"b0_test_2"});
        obj_b1.set_attribute_value("name", db::value{"b1_test_2"});
        obj_a.set_relation_objects("child", {obj_b1, obj_b0});

        XCTAssertEqual(obj_a.status(), db::object_status::changed);
        XCTAssertEqual(obj_b0.status(), db::object_status::changed);
        XCTAssertEqual(obj_b1.status(), db::object_status::changed);

        XCTAssertTrue(manager.has_changed_objects());
    });

    manager.reset(db::no_cancellation, [self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertFalse(manager.has_changed_objects());

        auto &obj_a = objects.at("sample_a").at(0);
        auto &obj_b0 = objects.at("sample_b").at(0);
        auto &obj_b1 = objects.at("sample_b").at(1);

        XCTAssertEqual(obj_a.attribute_value("name"), db::value{"a_test_1"});
        XCTAssertEqual(obj_b0.attribute_value("name"), db::value{"b0_test_1"});
        XCTAssertEqual(obj_b1.attribute_value("name"), db::value{"b1_test_1"});
        XCTAssertEqual(obj_a.relation_size("child"), 1);
        XCTAssertEqual(manager.relation_object_at(obj_a, "child", 0), obj_b0);

        XCTAssertEqual(obj_a.status(), db::object_status::saved);
        XCTAssertEqual(obj_b0.status(), db::object_status::saved);
        XCTAssertEqual(obj_b1.status(), db::object_status::saved);
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_invert_relation_removed_in_cache {
    // フェッチされていないオブジェクトに逆関連があった場合に、キャッシュ上のオブジェクトから削除されているかテスト

    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"setup"];

        manager.setup([self, &manager, exp](auto result) { [exp fulfill]; });

        [self waitForExpectations:@[exp] timeout:10.0];
    }

    db::object_vector_map_t objects;

    {
        // sample_aとsample_bのオブジェクトを1つずつ挿入する

        XCTestExpectation *exp = [self expectationWithDescription:@"insert"];

        manager.insert_objects(db::no_cancellation,
                               []() {
                                   return db::entity_count_map_t{{"sample_a", 1}, {"sample_b", 1}};
                               },
                               [&objects, exp](auto result) {
                                   if (result) {
                                       objects = std::move(result.value());
                                   }

                                   [exp fulfill];
                               });

        [self waitForExpectations:@[exp] timeout:10.0];
    }

    {
        db::object &obj_a = objects.at("sample_a").at(0);
        db::object &obj_b = objects.at("sample_b").at(0);

        // 関連をセット
        obj_a.set_relation_objects("child", {obj_b});
    }

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"save"];

        manager.save(db::no_cancellation, [exp](db::manager_map_result_t result) { [exp fulfill]; });

        [self waitForExpectations:@[exp] timeout:10.0];
    }

    {
        db::object &obj_a = objects.at("sample_a").at(0);
        db::object &obj_b = objects.at("sample_b").at(0);

        // obj_bを削除
        obj_b.remove();

        // キャッシュ上のobj_aから関連が取り除かれている
        XCTAssertEqual(manager.relation_objects(obj_a, "child").size(), 0);
    }

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"save"];

        manager.save(db::no_cancellation, [exp](db::manager_map_result_t result) { [exp fulfill]; });

        [self waitForExpectations:@[exp] timeout:10.0];
    }

    {
        // キャッシュをクリア
        objects.clear();
    }

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"fetch"];

        db::object_vector_map_t fetched_objects;

        manager.fetch_objects(
            db::no_cancellation,
            []() {
                return db::to_fetch_option(db::select_option{
                    .table = "sample_a", .field_orders = {{db::object_id_field, db::order::ascending}}});
            },
            [exp, &fetched_objects](db::manager_vector_result_t result) {
                fetched_objects = std::move(result.value());
                [exp fulfill];
            });

        [self waitForExpectations:@[exp] timeout:10.0];

        auto const &a_objects = fetched_objects.at("sample_a");
        XCTAssertEqual(a_objects.size(), 1);

        // 関連が取り除かれた状態でDBに保存されていることを確認
        auto const &obj_a = a_objects.at(0);
        XCTAssertEqual(manager.relation_objects(obj_a, "child").size(), 0);
    }
}

- (void)test_invert_relation_removed_in_db {
    // フェッチされていないオブジェクトに逆関連があった場合に、DB上で関連を削除されているかテスト

    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"setup"];

        manager.setup([self, &manager, exp](auto result) { [exp fulfill]; });

        [self waitForExpectations:@[exp] timeout:10.0];
    }

    db::object_vector_map_t objects;

    {
        // sample_aとsample_bのオブジェクトを3つずつ挿入する

        XCTestExpectation *exp = [self expectationWithDescription:@"insert"];

        manager.insert_objects(db::no_cancellation,
                               []() {
                                   return db::entity_count_map_t{{"sample_a", 3}, {"sample_b", 3}};
                               },
                               [&objects, exp](auto result) {
                                   if (result) {
                                       objects = std::move(result.value());
                                   }

                                   [exp fulfill];
                               });

        [self waitForExpectations:@[exp] timeout:10.0];
    }

    XCTAssertEqual(manager.current_save_id(), db::value{1});

    db::object_id obj_a0_id = db::null_id();
    db::object_id obj_a1_id = db::null_id();
    db::object_id obj_a2_id = db::null_id();
    db::object_id obj_b0_id = db::null_id();
    db::object_id obj_b1_id = db::null_id();
    db::object_id obj_b2_id = db::null_id();

    {
        db::object &obj_a0 = objects.at("sample_a").at(0);
        db::object &obj_a1 = objects.at("sample_a").at(1);
        db::object &obj_a2 = objects.at("sample_a").at(2);
        db::object &obj_b0 = objects.at("sample_b").at(0);
        db::object &obj_b1 = objects.at("sample_b").at(1);
        db::object &obj_b2 = objects.at("sample_b").at(2);

        obj_a0_id = obj_a0.object_id();
        obj_a1_id = obj_a1.object_id();
        obj_a2_id = obj_a2.object_id();
        obj_b0_id = obj_b0.object_id();
        obj_b1_id = obj_b1.object_id();
        obj_b2_id = obj_b2.object_id();

        // 関連のセット
        obj_a0.set_relation_objects("child", {obj_b0});
        obj_a1.set_relation_objects("child", {obj_b2});
        obj_a2.set_relation_objects("child", {obj_b2});
    }

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"save1"];

        manager.save(db::no_cancellation, [exp](db::manager_map_result_t result) { [exp fulfill]; });

        [self waitForExpectations:@[exp] timeout:10.0];

        XCTAssertEqual(manager.current_save_id(), db::value{2});
    }

    {
        db::object &obj_a0 = objects.at("sample_a").at(0);
        db::object &obj_b0 = objects.at("sample_b").at(0);
        db::object &obj_b1 = objects.at("sample_b").at(1);

        // obj_a0の関連にobj_b1、obj_b0をセットする
        obj_a0.set_relation_objects("child", {obj_b1, obj_b0});
    }

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"save2"];

        manager.save(db::no_cancellation, [exp](db::manager_map_result_t result) { [exp fulfill]; });

        [self waitForExpectations:@[exp] timeout:10.0];

        XCTAssertEqual(manager.current_save_id(), db::value{3});
    }

    {
        // obj_a1を変更
        db::object &obj_a1 = objects.at("sample_a").at(1);
        obj_a1.set_attribute_value("name", db::value{"test_name_x"});

        // obj_a2を削除
        db::object &obj_a2 = objects.at("sample_a").at(2);
        obj_a2.remove();
    }

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"save3"];

        manager.save(db::no_cancellation, [exp](db::manager_map_result_t result) { [exp fulfill]; });

        [self waitForExpectations:@[exp] timeout:10.0];

        XCTAssertEqual(manager.current_save_id(), db::value{4});
    }

    {
        // sample_aのオブジェクトをキャッシュから削除してデータベースに影響ないようにする

        db::object &obj_a0 = objects.at("sample_a").at(0);
        db::object &obj_a1 = objects.at("sample_a").at(1);
        db::object &obj_a2 = objects.at("sample_a").at(2);

        XCTAssertEqual(obj_a0.save_id(), db::value{3});
        XCTAssertEqual(obj_a1.save_id(), db::value{4});
        XCTAssertEqual(obj_a2.save_id(), db::value{4});
        XCTAssertTrue(obj_a2.is_removed());

        objects.erase("sample_a");

        XCTAssertEqual(objects.count("sample_a"), 0);
    }

    {
        // キャッシュが残っていないことを確認
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a0_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a1_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a2_id));
    }

    {
        // sample_aを全て取得
        // obj_a0にobj_b1、obj_b0
        // obj_a1にobj_b2

        XCTestExpectation *exp = [self expectationWithDescription:@"fetch"];

        db::object_vector_map_t fetched_objects;

        manager.fetch_objects(
            db::no_cancellation,
            []() {
                return db::to_fetch_option(db::select_option{
                    .table = "sample_a", .field_orders = {{db::object_id_field, db::order::ascending}}});
            },
            [exp, &fetched_objects](db::manager_vector_result_t result) {
                fetched_objects = std::move(result.value());
                [exp fulfill];
            });

        [self waitForExpectations:@[exp] timeout:10.0];

        auto const &a_objects = fetched_objects.at("sample_a");
        XCTAssertEqual(a_objects.size(), 2);

        auto const &obj_a0 = a_objects.at(0);
        auto const &obj_a0_rels = manager.relation_objects(obj_a0, "child");
        XCTAssertEqual(obj_a0_rels.size(), 2);
        XCTAssertEqual(obj_a0_rels.at(0).object_id().stable_value(), obj_b1_id.stable_value());
        XCTAssertEqual(obj_a0_rels.at(1).object_id().stable_value(), obj_b0_id.stable_value());

        auto const &obj_a1 = a_objects.at(1);
        XCTAssertEqual(manager.relation_objects(obj_a1, "child").size(), 1);
        auto const &obj_a1_rels = manager.relation_objects(obj_a1, "child");
        XCTAssertEqual(obj_a1_rels.at(0).object_id().stable_value(), obj_b2_id.stable_value());
    }

    {
        // キャッシュが残っていないことを確認
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a0_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a1_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a2_id));
    }

    {
        // obj_b0をremove
        db::object &obj_b0 = objects.at("sample_b").at(0);
        obj_b0.remove();
    }

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"save4"];

        manager.save(db::no_cancellation, [exp](db::manager_map_result_t result) { [exp fulfill]; });

        [self waitForExpectations:@[exp] timeout:10.0];

        XCTAssertEqual(manager.current_save_id(), db::value{5});
    }

    {
        // sample_aを全て取得
        // obj_a0にobj_b1
        // obj_a1にobj_b2

        XCTestExpectation *exp = [self expectationWithDescription:@"fetch"];

        db::object_vector_map_t fetched_objects;

        manager.fetch_objects(
            db::no_cancellation,
            []() {
                return db::to_fetch_option(db::select_option{
                    .table = "sample_a", .field_orders = {{db::object_id_field, db::order::ascending}}});
            },
            [exp, &fetched_objects](db::manager_vector_result_t result) {
                fetched_objects = std::move(result.value());
                [exp fulfill];
            });

        [self waitForExpectations:@[exp] timeout:10.0];

        auto const &a_objects = fetched_objects.at("sample_a");
        XCTAssertEqual(a_objects.size(), 2);

        auto const &obj_a0 = a_objects.at(0);
        auto const &obj_a0_rels = manager.relation_objects(obj_a0, "child");
        XCTAssertEqual(obj_a0_rels.size(), 1);
        XCTAssertEqual(obj_a0_rels.at(0).object_id().stable_value(), obj_b1_id.stable_value());

        auto const &obj_a1 = a_objects.at(1);
        XCTAssertEqual(manager.relation_objects(obj_a1, "child").size(), 1);
        auto const &obj_a1_rels = manager.relation_objects(obj_a1, "child");
        XCTAssertEqual(obj_a1_rels.at(0).object_id().stable_value(), obj_b2_id.stable_value());
    }

    {
        // キャッシュが残っていないことを確認
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a0_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a1_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a2_id));
    }

    {
        // obj_b1をremove
        db::object &obj_b1 = objects.at("sample_b").at(1);
        obj_b1.remove();
    }

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"save5"];

        manager.save(db::no_cancellation, [exp](db::manager_map_result_t result) { [exp fulfill]; });

        [self waitForExpectations:@[exp] timeout:10.0];

        XCTAssertEqual(manager.current_save_id(), db::value{6});
    }

    {
        // sample_aを全て取得
        // obj_a0に関連なし
        // obj_a1にobj_b2

        XCTestExpectation *exp = [self expectationWithDescription:@"fetch"];

        db::object_vector_map_t fetched_objects;

        manager.fetch_objects(
            db::no_cancellation,
            []() {
                return db::to_fetch_option(db::select_option{
                    .table = "sample_a", .field_orders = {{db::object_id_field, db::order::ascending}}});
            },
            [exp, &fetched_objects](db::manager_vector_result_t result) {
                fetched_objects = std::move(result.value());
                [exp fulfill];
            });

        [self waitForExpectations:@[exp] timeout:10.0];

        auto const &a_objects = fetched_objects.at("sample_a");
        XCTAssertEqual(a_objects.size(), 2);

        auto const &obj_a0 = a_objects.at(0);
        auto const &obj_a0_rels = manager.relation_objects(obj_a0, "child");
        XCTAssertEqual(obj_a0_rels.size(), 0);

        auto const &obj_a1 = a_objects.at(1);
        XCTAssertEqual(manager.relation_objects(obj_a1, "child").size(), 1);
        auto const &obj_a1_rels = manager.relation_objects(obj_a1, "child");
        XCTAssertEqual(obj_a1_rels.at(0).object_id().stable_value(), obj_b2_id.stable_value());
    }

    {
        // キャッシュが残っていないことを確認
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a0_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a1_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a2_id));
    }

    {
        // obj_b2をremove
        db::object &obj_b2 = objects.at("sample_b").at(2);
        obj_b2.remove();
    }

    {
        XCTestExpectation *exp = [self expectationWithDescription:@"save6"];

        manager.save(db::no_cancellation, [exp](db::manager_map_result_t result) { [exp fulfill]; });

        [self waitForExpectations:@[exp] timeout:10.0];

        XCTAssertEqual(manager.current_save_id(), db::value{7});
    }

    {
        // sample_bのオブジェクトをキャッシュから削除する
        objects.erase("sample_b");

        XCTAssertEqual(objects.count("sample_b"), 0);
    }

    {
        // キャッシュが残っていないことを確認
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a0_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a1_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_a", obj_a2_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_b", obj_b0_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_b", obj_b1_id));
        XCTAssertFalse(manager.cached_or_created_object("sample_b", obj_b2_id));
    }

    {
        // sample_aを全て取得
        // 関連は全て外れている

        XCTestExpectation *exp = [self expectationWithDescription:@"fetch"];

        db::object_vector_map_t fetched_objects;

        manager.fetch_objects(
            db::no_cancellation,
            []() {
                return db::to_fetch_option(db::select_option{
                    .table = "sample_a", .field_orders = {{db::object_id_field, db::order::ascending}}});
            },
            [exp, &fetched_objects](db::manager_vector_result_t result) {
                fetched_objects = std::move(result.value());
                [exp fulfill];
            });

        [self waitForExpectations:@[exp] timeout:10.0];

        auto const &a_objects = fetched_objects.at("sample_a");
        XCTAssertEqual(a_objects.size(), 2);

        auto const &obj_a0 = a_objects.at(0);
        XCTAssertEqual(manager.relation_objects(obj_a0, "child").size(), 0);

        auto const &obj_a1 = a_objects.at(1);
        XCTAssertEqual(manager.relation_objects(obj_a1, "child").size(), 0);
    }
}

- (void)test_observing_object_changed {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self, &manager](auto result) {
                               XCTAssertTrue(result);

                               bool observer_called = false;

                               auto observer =
                                   manager.chain_db_object()
                                       .perform([&observer_called](db::object const &) { observer_called = true; })
                                       .end();

                               auto &object = result.value().at("sample_a").at(0);
                               object.set_attribute_value("name", db::value{"test_name"});

                               XCTAssertTrue(observer_called);
                           });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_observing_db_info_changed {
    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    std::size_t observing_count = 0;

    auto observer = manager.chain_db_info().perform([&observing_count](db::info const &) { ++observing_count; }).end();

    manager.setup([self, &manager, &observing_count](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(observing_count, 1);
    });

    manager.insert_objects(db::no_cancellation,
                           []() {
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self, &manager, &observing_count](auto result) {
                               XCTAssertEqual(observing_count, 2);

                               auto &object = result.value().at("sample_a").at(0);
                               object.set_attribute_value("name", db::value{"test_name"});
                           });

    manager.save(db::no_cancellation,
                 [self, &observing_count](db::manager_map_result_t result) { XCTAssertEqual(observing_count, 3); });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_dispatch_queue {
    dispatch_queue_t queue = dispatch_queue_create("test", DISPATCH_QUEUE_SERIAL);

    db::model model_0_0_1 = [yas_db_test_utils model_0_0_1];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1) priority_count:1 dispatch_queue:queue];

    XCTAssertEqualObjects(manager.dispatch_queue(), queue);

    manager.setup([self](auto result) { XCTAssertFalse([NSThread isMainThread]); });

    manager.insert_objects(db::no_cancellation,
                           [self]() {
                               XCTAssertFalse([NSThread isMainThread]);
                               return db::entity_count_map_t{{"sample_a", 1}};
                           },
                           [self](auto result) {
                               XCTAssertFalse([NSThread isMainThread]);
                               auto &object = result.value().at("sample_a").at(0);
                               object.set_attribute_value("name", db::value{"x"});
                           });

    manager.save(db::no_cancellation,
                 [self](db::manager_map_result_t result) { XCTAssertFalse([NSThread isMainThread]); });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];
    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)test_make_error {
    auto error = db::manager_error{db::manager_error_type::version_not_found};
    XCTAssertTrue(error);
    XCTAssertEqual(error.type(), db::manager_error_type::version_not_found);
}

- (void)test_error_none {
    db::manager_error error{nullptr};
    XCTAssertFalse(error);
    XCTAssertEqual(error.type(), db::manager_error_type::none);
}

- (void)test_to_string_from_error {
    XCTAssertEqual(to_string(db::manager_error_type::begin_transaction_failed), "begin_transaction_failed");
    XCTAssertEqual(to_string(db::manager_error_type::vacuum_failed), "vacuum_failed");
    XCTAssertEqual(to_string(db::manager_error_type::select_info_failed), "select_info_failed");
    XCTAssertEqual(to_string(db::manager_error_type::update_info_failed), "update_info_failed");
    XCTAssertEqual(to_string(db::manager_error_type::version_not_found), "version_not_found");
    XCTAssertEqual(to_string(db::manager_error_type::invalid_version_text), "invalid_version_text");
    XCTAssertEqual(to_string(db::manager_error_type::alter_entity_table_failed), "alter_entity_table_failed");
    XCTAssertEqual(to_string(db::manager_error_type::create_info_table_failed), "create_info_table_failed");
    XCTAssertEqual(to_string(db::manager_error_type::insert_info_failed), "insert_info_failed");
    XCTAssertEqual(to_string(db::manager_error_type::create_entity_table_failed), "create_entity_table_failed");
    XCTAssertEqual(to_string(db::manager_error_type::create_relation_table_failed), "create_relation_table_failed");
    XCTAssertEqual(to_string(db::manager_error_type::create_index_failed), "create_index_failed");
    XCTAssertEqual(to_string(db::manager_error_type::insert_attributes_failed), "insert_attributes_failed");
    XCTAssertEqual(to_string(db::manager_error_type::insert_relation_failed), "insert_relation_failed");
    XCTAssertEqual(to_string(db::manager_error_type::save_id_not_found), "save_id_not_found");
    XCTAssertEqual(to_string(db::manager_error_type::update_save_id_failed), "update_save_id_failed");
    XCTAssertEqual(to_string(db::manager_error_type::delete_failed), "delete_failed");
    XCTAssertEqual(to_string(db::manager_error_type::purge_failed), "purge_failed");
    XCTAssertEqual(to_string(db::manager_error_type::purge_relation_failed), "purge_relation_failed");
    XCTAssertEqual(to_string(db::manager_error_type::select_last_failed), "select_last_failed");
    XCTAssertEqual(to_string(db::manager_error_type::select_revert_failed), "select_revert_failed");
    XCTAssertEqual(to_string(db::manager_error_type::select_relation_removed_failed), "select_relation_removed_failed");
    XCTAssertEqual(to_string(db::manager_error_type::make_object_datas_failed), "make_object_datas_failed");
    XCTAssertEqual(to_string(db::manager_error_type::out_of_range_save_id), "out_of_range_save_id");
    XCTAssertEqual(to_string(db::manager_error_type::select_failed), "select_failed");
    XCTAssertEqual(to_string(db::manager_error_type::last_insert_rowid_failed), "last_insert_rowid_failed");
    XCTAssertEqual(to_string(db::manager_error_type::none), "none");
}

@end
