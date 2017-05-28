//
//  yas_db_additional_utils_tests.mm
//

#import "yas_db_test_utils.h"
#import "yas_db_additional_utils.h"

using namespace yas;

@interface yas_db_additional_utils_tests : XCTestCase

@end

@implementation yas_db_additional_utils_tests

- (void)setUp {
    [super setUp];
    [yas_db_test_utils deleteDatabase];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_select_last {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name, db::action_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;

    args = {db::value{1}, db::value{"value_1"}, db::insert_action_value()};

    auto result = db.execute_update(db::insert_sql(table_name, fields), args);
    XCTAssertTrue(result);
    args = {db::value{2}, db::value{"value_2"}, db::insert_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_last(db, db::select_option{.table = table_name});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2");

    args = {db::value{1}, db::value{"value_1_1"}, db::update_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    select_result = db::select_last(db, db::select_option{.table = table_name});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_1_1");

    args = {db::value{1}, db::null_value(), db::remove_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    select_result = db::select_last(db, db::select_option{.table = table_name});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2");
}

- (void)test_select_last_by_save_id {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    auto const insert_action_value = db::insert_action_value();
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field, db::action_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}, insert_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}, insert_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}, insert_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_b"}, db::value{2}, insert_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_c"}, db::value{3}, insert_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_c"}, db::value{4}, insert_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_last(db, db::select_option{.table = table_name}, db::value{4});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_c");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_c");

    select_result = db::select_last(db, db::select_option{.table = table_name}, db::value{2});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_b");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_b");

    select_result = db::select_last(db, db::select_option{.table = table_name}, db::value{3});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2_b");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_1_c");

    select_result = db::select_last(db, db::select_option{.table = table_name}, db::value{1});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_a");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_a");
}

- (void)test_select_last_with_addtional_parameters {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    auto const insert_action_value = db::insert_action_value();
    auto const update_action_value = db::update_action_value();
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field, db::action_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}, insert_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}, insert_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}, update_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_b"}, db::value{2}, update_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_c"}, db::value{3}, update_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_c"}, db::value{4}, update_action_value};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_last(
        db, db::select_option{.table = table_name, .field_orders = {{db::object_id_field, db::order::ascending}}},
        db::value{3});

    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_c");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_b");

    select_result = db::select_last(
        db,
        db::select_option{
            .table = table_name, .field_orders = {{db::object_id_field, db::order::descending}}, .limit_range = {0, 1}},
        db::value{3});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2_b");
}

- (void)test_select_undo {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field, db::action_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}, db::insert_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}, db::insert_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}, db::update_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{2}, db::value{"value_2_c"}, db::value{3}, db::update_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_d"}, db::value{4}, db::update_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_d"}, db::value{4}, db::update_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_undo(db, table_name, 3, 4);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_b");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_c");

    select_result = db::select_undo(db, table_name, 1, 3);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_a");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_a");

    select_result = db::select_undo(db, table_name, 2, 3);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2_a");

    select_result = db::select_undo(db, table_name, 1, 2);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_a");

    select_result = db::select_undo(db, table_name, 1, 4);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_a");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_a");

    select_result = db::select_undo(db, table_name, 0, 1);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).count(db::object_id_field), 1);
    XCTAssertEqual(select_result.value().at(0).at(db::object_id_field), db::value{1});
    XCTAssertEqual(select_result.value().at(0).count(field_name), 0);
    XCTAssertEqual(select_result.value().at(0).count(db::save_id_field), 0);
    XCTAssertEqual(select_result.value().at(0).count(db::action_field), 0);
    XCTAssertEqual(select_result.value().at(1).count(db::object_id_field), 1);
    XCTAssertEqual(select_result.value().at(1).at(db::object_id_field), db::value{2});
    XCTAssertEqual(select_result.value().at(1).count(field_name), 0);
    XCTAssertEqual(select_result.value().at(1).count(db::save_id_field), 0);
    XCTAssertEqual(select_result.value().at(1).count(db::action_field), 0);
}

- (void)test_select_redo {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{2}, db::value{"value_2_c"}, db::value{3}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_d"}, db::value{4}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_d"}, db::value{4}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_redo(db, table_name, 4, 3);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_d");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_d");

    select_result = db::select_redo(db, table_name, 3, 1);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_b");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_c");

    select_result = db::select_redo(db, table_name, 3, 2);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2_c");

    select_result = db::select_redo(db, table_name, 2, 1);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_b");

    select_result = db::select_redo(db, table_name, 4, 1);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_d");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_d");
}

- (void)test_select_revert {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field, db::action_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}, db::insert_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}, db::insert_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}, db::update_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{2}, db::value{"value_2_c"}, db::value{3}, db::update_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_d"}, db::value{4}, db::update_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_d"}, db::value{4}, db::update_action_value()};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_revert(db, table_name, 1, 4);

    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_a");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_a");

    select_result = db::select_revert(db, table_name, 4, 1);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_d");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_d");

    select_result = db::select_revert(db, table_name, 3, 3);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 0);

    select_result = db::select_revert(db, table_name, 0, 4);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).count(db::object_id_field), 1);
    XCTAssertEqual(select_result.value().at(0).count(field_name), 0);
    XCTAssertEqual(select_result.value().at(1).count(db::object_id_field), 1);
    XCTAssertEqual(select_result.value().at(1).count(field_name), 0);
}

- (void)test_purge {
    db::model model_0_0_2{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_2]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self, &manager](auto result) mutable { XCTAssertTrue(result); });

    manager.insert_objects(
        []() {
            return db::entity_count_map_t{{"sample_a", 2}};
        },
        [self, &manager](auto result) {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{1});

            auto &objects = result.value();
            auto &a_objects = objects.at("sample_a");

            auto &object = a_objects.at(0);
            object.set_attribute_value("name", db::value{"name_0_1"});
            XCTAssertEqual(object.object_id(), db::value{1});

            object = a_objects.at(1);
            object.set_attribute_value("name", db::value{"name_1_1"});
            XCTAssertEqual(object.object_id(), db::value{2});
        });

    manager.save([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{2});

        auto &objects = result.value();
        auto &a_objects = objects.at("sample_a");

        for (auto &object : a_objects) {
            if (object.object_id() == db::value{1}) {
                object.set_attribute_value("name", db::value{"name_0_2"});
            }
        }
    });

    manager.save([self, &manager](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{3});
    });

    manager.execute([self, &manager](auto const &op) {
        auto &db = manager.database();

        auto update_result = db::purge(db, "sample_a");
        XCTAssertTrue(update_result);

        auto select_result = db::select(db, db::select_option{.table = "sample_a"});
        XCTAssertTrue(select_result);

        auto &object_datas = select_result.value();
        XCTAssertEqual(object_datas.size(), 2);

        XCTAssertEqual(object_datas.at(0).at("obj_id"), db::value{2});
        XCTAssertEqual(object_datas.at(0).at("name"), db::value{"name_1_1"});

        XCTAssertEqual(object_datas.at(1).at("obj_id"), db::value{1});
        XCTAssertEqual(object_datas.at(1).at("name"), db::value{"name_0_2"});
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];

    manager.execute([exp](auto const &op) { [exp fulfill]; });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_purge_relations {
    db::model model_0_0_1{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_1]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_1)];

    manager.setup([self, &manager](auto result) { XCTAssertTrue(result); });

    db::object_vector_map_t objects;

    manager.insert_objects(
        []() {
            return db::entity_count_map_t{{"sample_a", 1}, {"sample_b", 2}};
        },
        [self, &manager, &objects](auto result) {
            XCTAssertTrue(result);
            XCTAssertEqual(manager.current_save_id(), db::value{1});

            objects = std::move(result.value());
            db::object &obj_a = objects.at("sample_a").at(0);
            db::object &obj_b0 = objects.at("sample_b").at(0);
            db::object &obj_b1 = objects.at("sample_b").at(1);

            obj_a.set_attribute_value("name", db::value{"test_a_2"});
            obj_b0.set_attribute_value("name", db::value{"test_b0_2"});
            obj_b1.set_attribute_value("name", db::value{"test_b1_2"});

            obj_a.set_relation_objects("child", {obj_b0});
        });

    manager.save([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{2});

        db::object &obj_a = objects.at("sample_a").at(0);
        db::object &obj_b0 = objects.at("sample_b").at(0);
        db::object &obj_b1 = objects.at("sample_b").at(1);

        obj_a.set_attribute_value("name", db::value{"test_a_3"});
        obj_b0.set_attribute_value("name", db::value{"test_b0_3"});
        obj_b1.set_attribute_value("name", db::value{"test_b1_3"});

        obj_a.set_relation_objects("child", {obj_b1, obj_b0});
    });

    manager.save([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{3});

        db::object &obj_a = objects.at("sample_a").at(0);
        db::object &obj_b0 = objects.at("sample_b").at(0);
        db::object &obj_b1 = objects.at("sample_b").at(1);

        obj_a.set_attribute_value("name", db::value{"test_a_4"});
        obj_b0.set_attribute_value("name", db::value{"test_b0_4"});
        obj_b1.set_attribute_value("name", db::value{"test_b1_4"});

        obj_a.set_relation_objects("child", {obj_b1});
    });

    manager.save([self, &manager, &objects](auto result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{4});
    });

    manager.execute([self, &manager](auto const &op) {
        auto &db = manager.database();

        auto purge_result = db::purge(db, "sample_a");
        XCTAssertTrue(purge_result);

        auto const &rel_table_name = manager.model().entities().at("sample_a").relations.at("child").table_name;

        auto purge_relation_result = db::purge_relation(db, rel_table_name, "sample_a");
        XCTAssertTrue(purge_relation_result);

        auto select_result = db::select(db, db::select_option{.table = rel_table_name});
        XCTAssertTrue(select_result);

        auto &entity_rel_values = select_result.value();
        XCTAssertEqual(entity_rel_values.size(), 1);

        auto &rel_values = entity_rel_values.at(0);
        XCTAssertEqual(rel_values.at(db::src_pk_id_field), db::value{4});
        XCTAssertEqual(rel_values.at(db::src_obj_id_field), db::value{1});
        XCTAssertEqual(rel_values.at(db::tgt_obj_id_field), db::value{2});
    });

    XCTestExpectation *exp = [self expectationWithDescription:@"exp"];

    manager.execute([exp](auto const &op) { [exp fulfill]; });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

@end
