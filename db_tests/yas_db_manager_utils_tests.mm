//
//  yas_db_manager_utils_tests.mm
//

#import <db/yas_db_manager_utils.h>
#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_manager_utils_tests : XCTestCase

@end

@implementation yas_db_manager_utils_tests

- (void)setUp {
    [super setUp];
    [yas_db_test_utils deleteDatabase];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_select_last {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name, db::action_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;

    args = {db::value{1}, db::value{"value_1"}, db::insert_action_value()};

    auto result = db->execute_update(db::insert_sql(table_name, fields), args);
    XCTAssertTrue(result);
    args = {db::value{2}, db::value{"value_2"}, db::insert_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_last(db, db::select_option{.table = table_name});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2");

    args = {db::value{1}, db::value{"value_1_1"}, db::update_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    select_result = db::select_last(db, db::select_option{.table = table_name});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_1_1");

    args = {db::value{1}, db::null_value(), db::remove_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    select_result = db::select_last(db, db::select_option{.table = table_name});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2");
}

- (void)test_select_last_by_save_id {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    auto const insert_action_value = db::insert_action_value();
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field, db::action_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}, insert_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}, insert_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}, insert_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_b"}, db::value{2}, insert_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_c"}, db::value{3}, insert_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_c"}, db::value{4}, insert_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

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
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    auto const insert_action_value = db::insert_action_value();
    auto const update_action_value = db::update_action_value();
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field, db::action_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}, insert_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}, insert_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}, update_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_b"}, db::value{2}, update_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_c"}, db::value{3}, update_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_c"}, db::value{4}, update_action_value};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

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
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field, db::action_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}, db::insert_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}, db::insert_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}, db::update_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{2}, db::value{"value_2_c"}, db::value{3}, db::update_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_d"}, db::value{4}, db::update_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_d"}, db::value{4}, db::update_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_for_undo(db, table_name, 3, 4);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_b");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_c");

    select_result = db::select_for_undo(db, table_name, 1, 3);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_a");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_a");

    select_result = db::select_for_undo(db, table_name, 2, 3);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2_a");

    select_result = db::select_for_undo(db, table_name, 1, 2);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_a");

    select_result = db::select_for_undo(db, table_name, 1, 4);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_a");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_a");

    select_result = db::select_for_undo(db, table_name, 0, 1);
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
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{2}, db::value{"value_2_c"}, db::value{3}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_d"}, db::value{4}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_d"}, db::value{4}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_for_redo(db, table_name, 4, 3);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_d");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_d");

    select_result = db::select_for_redo(db, table_name, 3, 1);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_b");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_c");

    select_result = db::select_for_redo(db, table_name, 3, 2);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2_c");

    select_result = db::select_for_redo(db, table_name, 2, 1);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_b");

    select_result = db::select_for_redo(db, table_name, 4, 1);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_d");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_d");
}

- (void)test_select_revert {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field, db::action_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}, db::insert_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}, db::insert_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}, db::update_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{2}, db::value{"value_2_c"}, db::value{3}, db::update_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_d"}, db::value{4}, db::update_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_d"}, db::value{4}, db::update_action_value()};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_for_revert(db, table_name, 1, 4);

    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_a");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_a");

    select_result = db::select_for_revert(db, table_name, 4, 1);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_d");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_d");

    select_result = db::select_for_revert(db, table_name, 3, 3);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 0);

    select_result = db::select_for_revert(db, table_name, 0, 4);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).count(db::object_id_field), 1);
    XCTAssertEqual(select_result.value().at(0).count(field_name), 0);
    XCTAssertEqual(select_result.value().at(1).count(db::object_id_field), 1);
    XCTAssertEqual(select_result.value().at(1).count(field_name), 0);
}

- (void)test_purge_attributes {
    db::model model_0_0_2 = [yas_db_test_utils model_0_0_2];
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    manager.setup([self, &manager](auto result) mutable { XCTAssertTrue(result); });

    manager.insert_objects(db::no_cancellation,
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
                               XCTAssertEqual(object.object_id().stable_value(), db::value{1});

                               object = a_objects.at(1);
                               object.set_attribute_value("name", db::value{"name_1_1"});
                               XCTAssertEqual(object.object_id().stable_value(), db::value{2});
                           });

    manager.save(db::no_cancellation, [self, &manager](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{2});

        db::object_map_map_t &objects = result.value();
        db::object_map_t &a_objects = objects.at("sample_a");

        db::object &object = a_objects.at(1);
        object.set_attribute_value("name", db::value{"name_0_2"});
    });

    manager.save(db::no_cancellation, [self, &manager](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{3});
    });

    manager.execute(db::no_cancellation, [self, &manager](auto const &) {
        auto &db = manager.database();

        auto update_result = db::purge_attributes(db, "sample_a");
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

    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_purge_relations {
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

                               objects = std::move(result.value());
                               db::object &obj_a = objects.at("sample_a").at(0);
                               db::object &obj_b0 = objects.at("sample_b").at(0);
                               db::object &obj_b1 = objects.at("sample_b").at(1);

                               obj_a.set_attribute_value("name", db::value{"test_a_2"});
                               obj_b0.set_attribute_value("name", db::value{"test_b0_2"});
                               obj_b1.set_attribute_value("name", db::value{"test_b1_2"});

                               obj_a.set_relation_objects("child", {obj_b0});
                           });

    manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) {
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

    manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) {
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

    manager.save(db::no_cancellation, [self, &manager, &objects](db::manager_map_result_t result) {
        XCTAssertTrue(result);
        XCTAssertEqual(manager.current_save_id(), db::value{4});
    });

    manager.execute(db::no_cancellation, [self, &manager](auto const &) {
        auto &db = manager.database();

        auto purge_result = db::purge_attributes(db, "sample_a");
        XCTAssertTrue(purge_result);

        auto const &rel_table_name = manager.model().entities().at("sample_a").relations.at("child").table;

        auto purge_relation_result = db::purge_relations(db, rel_table_name, "sample_a");
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

    manager.execute(db::no_cancellation, [exp](auto const &) { [exp fulfill]; });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)test_to_stable_ids_from_vector {
    db::value_vector_t values{db::value{10}, db::value{11}};

    db::id_vector_t ids = db::to_stable_ids(values);

    XCTAssertEqual(ids.at(0), db::make_stable_id(10));
    XCTAssertEqual(ids.at(1), db::make_stable_id(11));
}

- (void)test_to_stable_ids_from_map {
    db::value_vector_map_t values;
    values.emplace("a", db::value_vector_t{db::value{10}, db::value{11}});
    values.emplace("b", db::value_vector_t{db::value{20}, db::value{21}});

    db::id_vector_map_t ids = db::to_stable_ids(values);

    XCTAssertEqual(ids.at("a").at(0), db::make_stable_id(10));
    XCTAssertEqual(ids.at("a").at(1), db::make_stable_id(11));
    XCTAssertEqual(ids.at("b").at(0), db::make_stable_id(20));
    XCTAssertEqual(ids.at("b").at(1), db::make_stable_id(21));
}

- (void)test_copy_ids {
    db::id_vector_t ids{db::make_stable_id(30), db::make_temporary_id()};

    db::id_vector_t copied_ids = db::copy_ids(ids);

    XCTAssertEqual(copied_ids.at(0), db::make_stable_id(30));
    XCTAssertEqual(copied_ids.at(1).temporary(), ids.at(1).temporary());
    XCTAssertNotEqual(copied_ids.at(0).identifier(), ids.at(0).identifier());
    XCTAssertNotEqual(copied_ids.at(1).identifier(), ids.at(1).identifier());
}

- (void)test_to_values_from_vector {
    db::id_vector_t ids{db::make_stable_id(40), db::make_stable_id(41)};

    db::value_vector_t values = db::to_values(ids);

    XCTAssertEqual(values.at(0), db::value{40});
    XCTAssertEqual(values.at(1), db::value{41});
}

- (void)test_to_values_from_map {
    db::id_vector_map_t ids;
    ids.emplace("a", db::id_vector_t{db::make_stable_id(50), db::make_stable_id(51)});
    ids.emplace("b", db::id_vector_t{db::make_stable_id(60), db::make_stable_id(61)});

    db::value_vector_map_t values = db::to_values(ids);

    XCTAssertEqual(values.at("a").at(0), db::value{50});
    XCTAssertEqual(values.at("a").at(1), db::value{51});
    XCTAssertEqual(values.at("b").at(0), db::value{60});
    XCTAssertEqual(values.at("b").at(1), db::value{61});
}

- (void)test_to_preparation_ids_from_objects {
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
    obj_c_1.add_relation_object("friend", obj_a_1);

    XCTestExpectation *saveExp = [self expectationWithDescription:@"save"];

    db::object_map_map_t saved_objects;

    manager.save(db::no_cancellation, [saveExp, &saved_objects](db::manager_map_result_t result) {
        saved_objects = std::move(result.value());

        [saveExp fulfill];
    });

    [self waitForExpectations:@[saveExp] timeout:10.0];

    db::object_vector_t objects{obj_a_1, obj_a_2, obj_c_1};

    db::fetch_ids_preparation_f ids_preparation = db::to_ids_preparation([objects]() { return objects; });

    db::integer_set_map_t const ids = ids_preparation();

    XCTAssertEqual(ids.size(), 3);

    db::integer_set_t const &entity_a_ids = ids.at("sample_a");
    XCTAssertEqual(entity_a_ids.size(), 1);
    XCTAssertEqual(entity_a_ids.count(obj_a_1.object_id().stable()), 1);

    db::integer_set_t const &entity_b_ids = ids.at("sample_b");

    XCTAssertEqual(entity_b_ids.size(), 4);
    XCTAssertEqual(entity_b_ids.count(obj_b_1.object_id().stable()), 1);
    XCTAssertEqual(entity_b_ids.count(obj_b_2.object_id().stable()), 1);
    XCTAssertEqual(entity_b_ids.count(obj_b_3.object_id().stable()), 1);
    XCTAssertEqual(entity_b_ids.count(obj_b_4.object_id().stable()), 1);

    db::integer_set_t const &entity_c_ids = ids.at("sample_c");

    XCTAssertEqual(entity_c_ids.size(), 1);
    XCTAssertEqual(entity_b_ids.count(obj_c_1.object_id().stable()), 1);
}

- (void)test_to_preparation_ids_from_object_map {
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
    obj_c_1.add_relation_object("friend", obj_a_1);

    XCTestExpectation *saveExp = [self expectationWithDescription:@"save"];

    db::object_map_map_t saved_objects;

    manager.save(db::no_cancellation, [saveExp, &saved_objects](db::manager_map_result_t result) {
        saved_objects = std::move(result.value());

        [saveExp fulfill];
    });

    [self waitForExpectations:@[saveExp] timeout:10.0];

    db::object_map_t entity_a_objects{{obj_a_1.object_id().stable(), obj_a_1}, {obj_a_2.object_id().stable(), obj_a_2}};
    db::object_map_t entity_c_objects{{obj_c_1.object_id().stable(), obj_c_1}};
    db::object_map_map_t objects{{"sample_a", std::move(entity_a_objects)}, {"sample_c", std::move(entity_c_objects)}};

    db::fetch_ids_preparation_f ids_preparation = db::to_ids_preparation([objects]() { return objects; });

    db::integer_set_map_t const ids = ids_preparation();

    XCTAssertEqual(ids.size(), 3);

    db::integer_set_t const &entity_a_ids = ids.at("sample_a");
    XCTAssertEqual(entity_a_ids.size(), 1);
    XCTAssertEqual(entity_a_ids.count(obj_a_1.object_id().stable()), 1);

    db::integer_set_t const &entity_b_ids = ids.at("sample_b");

    XCTAssertEqual(entity_b_ids.size(), 4);
    XCTAssertEqual(entity_b_ids.count(obj_b_1.object_id().stable()), 1);
    XCTAssertEqual(entity_b_ids.count(obj_b_2.object_id().stable()), 1);
    XCTAssertEqual(entity_b_ids.count(obj_b_3.object_id().stable()), 1);
    XCTAssertEqual(entity_b_ids.count(obj_b_4.object_id().stable()), 1);

    db::integer_set_t const &entity_c_ids = ids.at("sample_c");

    XCTAssertEqual(entity_c_ids.size(), 1);
    XCTAssertEqual(entity_b_ids.count(obj_c_1.object_id().stable()), 1);
}

- (void)test_to_preparation_ids_from_object_vector {
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
    obj_c_1.add_relation_object("friend", obj_a_1);

    XCTestExpectation *saveExp = [self expectationWithDescription:@"save"];

    db::object_map_map_t saved_objects;

    manager.save(db::no_cancellation, [saveExp, &saved_objects](db::manager_map_result_t result) {
        saved_objects = std::move(result.value());

        [saveExp fulfill];
    });

    [self waitForExpectations:@[saveExp] timeout:10.0];

    db::object_vector_t entity_a_objects{obj_a_1, obj_a_2};
    db::object_vector_t entity_c_objects{obj_c_1};
    db::object_vector_map_t objects{{"sample_a", std::move(entity_a_objects)},
                                    {"sample_c", std::move(entity_c_objects)}};

    db::fetch_ids_preparation_f ids_preparation = db::to_ids_preparation([objects]() { return objects; });

    db::integer_set_map_t const ids = ids_preparation();

    XCTAssertEqual(ids.size(), 3);

    db::integer_set_t const &entity_a_ids = ids.at("sample_a");
    XCTAssertEqual(entity_a_ids.size(), 1);
    XCTAssertEqual(entity_a_ids.count(obj_a_1.object_id().stable()), 1);

    db::integer_set_t const &entity_b_ids = ids.at("sample_b");

    XCTAssertEqual(entity_b_ids.size(), 4);
    XCTAssertEqual(entity_b_ids.count(obj_b_1.object_id().stable()), 1);
    XCTAssertEqual(entity_b_ids.count(obj_b_2.object_id().stable()), 1);
    XCTAssertEqual(entity_b_ids.count(obj_b_3.object_id().stable()), 1);
    XCTAssertEqual(entity_b_ids.count(obj_b_4.object_id().stable()), 1);

    db::integer_set_t const &entity_c_ids = ids.at("sample_c");

    XCTAssertEqual(entity_c_ids.size(), 1);
    XCTAssertEqual(entity_b_ids.count(obj_c_1.object_id().stable()), 1);
}

@end
