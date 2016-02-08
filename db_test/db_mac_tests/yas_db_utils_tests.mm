//
//  yas_db_utils_tests.mm
//

#import <XCTest/XCTest.h>
#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_utils_tests : XCTestCase

@end

@implementation yas_db_utils_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_table {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db::create_table(db, "test_table_a", {"field_a"}));
    XCTAssertTrue(db::create_table(db, "test_table_b", {"field_b"}));

    XCTAssertTrue(db::table_exists(db, "test_table_a"));
    XCTAssertTrue(db::table_exists(db, "test_table_b"));

    auto schema_set_1 = db::get_table_schema(db, "test_table_a");
    XCTAssertTrue(schema_set_1.next());
    XCTAssertEqual(schema_set_1.column_value("name").get<db::text>(), "field_a");
    XCTAssertFalse(schema_set_1.next());

    XCTAssertTrue(db::alter_table(db, "test_table_a", "field_c"));

    auto schema_set_2 = db::get_table_schema(db, "test_table_a");
    XCTAssertTrue(schema_set_2.next());
    XCTAssertEqual(schema_set_2.column_value("name").get<db::text>(), "field_a");
    XCTAssertTrue(schema_set_2.next());
    XCTAssertEqual(schema_set_2.column_value("name").get<db::text>(), "field_c");
    XCTAssertFalse(schema_set_2.next());

    XCTAssertTrue(db::drop_table(db, "test_table_b"));

    XCTAssertTrue(db::table_exists(db, "test_table_a"));
    XCTAssertFalse(db::table_exists(db, "test_table_b"));
}

- (void)test_transaction_commit {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(db::create_table_sql("test_table", {"test_field"})));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));

    auto query_result_1 = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result_1);
    XCTAssertTrue(query_result_1.value().next());
    XCTAssertFalse(query_result_1.value().next());

    XCTAssertTrue(db::begin_transaction(db));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value2')"));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value3')"));
    XCTAssertTrue(db::commit(db));

    auto query_result_2 = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result_2);
    XCTAssertTrue(query_result_2.value().next());
    XCTAssertTrue(query_result_2.value().next());
    XCTAssertTrue(query_result_2.value().next());
    XCTAssertFalse(query_result_2.value().next());
}

- (void)test_transaction_rollback {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(db::create_table_sql("test_table", {"test_field"})));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));

    auto query_result_1 = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result_1);
    XCTAssertTrue(query_result_1.value().next());
    XCTAssertFalse(query_result_1.value().next());

    XCTAssertTrue(db::begin_transaction(db));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value2')"));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value3')"));
    XCTAssertTrue(db::rollback(db));

    auto query_result_2 = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result_2);
    XCTAssertTrue(query_result_2.value().next());
    XCTAssertFalse(query_result_2.value().next());
}

- (void)test_save_point {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db::create_table(db, "test_table", {"test_field"}));

    auto count_of_row = [&db]() {
        auto query_result = db.execute_query("select * from test_table");
        int count = 0;
        while (query_result.value().next()) {
            ++count;
        }
        return count;
    };

    XCTAssertEqual(count_of_row(), 0);
    XCTAssertTrue(db::start_save_point(db, "sp_1"));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));
    XCTAssertEqual(count_of_row(), 1);
    XCTAssertTrue(db::start_save_point(db, "sp_2"));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value2')"));
    XCTAssertEqual(count_of_row(), 2);
    XCTAssertTrue(db::rollback_save_point(db, "sp_2"));
    XCTAssertEqual(count_of_row(), 1);
    XCTAssertTrue(db::release_save_point(db, "sp_1"));
    XCTAssertEqual(count_of_row(), 1);
}

- (void)test_in_save_point {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(db::create_table_sql("test_table", {"test_field"})));

    auto count_of_row = [&db]() {
        auto query_result = db.execute_query("select * from test_table");
        int count = 0;
        while (query_result.value().next()) {
            ++count;
        }
        return count;
    };

    XCTAssertTrue(db::in_save_point(db, [&db, &count_of_row, &self](bool &should_rollback) {
        XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));
        XCTAssertEqual(count_of_row(), 1);
    }));

    XCTAssertEqual(count_of_row(), 1);
}

- (void)test_in_save_point_rollback {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db::create_table(db, "test_table", {"test_field"}));

    auto count_of_row = [&db]() {
        auto query_result = db.execute_query("select * from test_table");
        int count = 0;
        while (query_result.value().next()) {
            ++count;
        }
        return count;
    };

    XCTAssertTrue(db::in_save_point(db, [&db, &count_of_row, &self](bool &should_rollback) {
        XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));
        XCTAssertEqual(count_of_row(), 1);
        should_rollback = true;
    }));

    XCTAssertEqual(count_of_row(), 0);
}

- (void)test_savepoint_failed {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertFalse(db::start_save_point(db, ""));
    XCTAssertFalse(db::release_save_point(db, ""));
    XCTAssertFalse(db::rollback_save_point(db, ""));
}

- (void)test_table_exists {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db::create_table(db, "test_table", {"field"}));

    XCTAssertTrue(db::table_exists(db, "test_table"));
    XCTAssertFalse(db::table_exists(db, "hoge"));
}

- (void)test_column_exists {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db::create_table(db, "test_table", {"field_a", "field_b"}));

    XCTAssertTrue(db::column_exists(db, "field_a", "test_table"));
    XCTAssertTrue(db::column_exists(db, "field_b", "test_table"));

    XCTAssertFalse(db::column_exists(db, "field_a", "hoge"));
    XCTAssertFalse(db::column_exists(db, "hage", "test_table"));
}

- (void)test_get_schema {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    std::string const sql = "create table test_table (test_field)";
    XCTAssertTrue(db.execute_update(sql));

    auto row_set = db::get_schema(db);
    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set.next());

    auto map = row_set.value_map();

    XCTAssertGreaterThan(map.count("sql"), 0);
    auto &sql_column_value = map.at("sql");
    XCTAssertTrue(sql_column_value.type() == typeid(db::text));
    XCTAssertEqual(yas::to_lower(sql_column_value.get<db::text>()), sql);

    XCTAssertGreaterThan(map.count("tbl_name"), 0);
    auto &tbl_name_column_value = map.at("tbl_name");
    XCTAssertTrue(tbl_name_column_value.type() == typeid(db::text));
    XCTAssertEqual(tbl_name_column_value.get<db::text>(), "test_table");

    XCTAssertGreaterThan(map.count("name"), 0);
    auto &name_column_value = map.at("name");
    XCTAssertTrue(name_column_value.type() == typeid(db::text));
    XCTAssertEqual(name_column_value.get<db::text>(), "test_table");

    XCTAssertGreaterThan(map.count("rootpage"), 0);
    auto &rootpage_column_value = map.at("rootpage");
    XCTAssertTrue(rootpage_column_value.type() == typeid(db::integer));
    XCTAssertEqual(sql_column_value.get<db::integer>(), 0);

    XCTAssertGreaterThan(map.count("type"), 0);
    auto &type_column_value = map.at("type");
    XCTAssertTrue(type_column_value.type() == typeid(db::text));
    XCTAssertEqual(type_column_value.get<db::text>(), "table");

    XCTAssertFalse(row_set.next());
}

- (void)test_get_table_schema {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db::create_table(db, "test_table", {"field_a", "field_b"}));

    auto row_set = db::get_table_schema(db, "test_table");
    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set.next());

    auto map = row_set.value_map();

    XCTAssertGreaterThan(map.count("pk"), 0);
    XCTAssertGreaterThan(map.count("dflt_value"), 0);
    XCTAssertGreaterThan(map.count("type"), 0);
    XCTAssertGreaterThan(map.count("notnull"), 0);
    XCTAssertGreaterThan(map.count("name"), 0);
    XCTAssertGreaterThan(map.count("cid"), 0);

    XCTAssertEqual(map.at("name").get<db::text>(), "field_a");

    XCTAssertTrue(row_set.next());

    map = row_set.value_map();

    XCTAssertEqual(map.at("name").get<db::text>(), "field_b");

    XCTAssertFalse(row_set.next());
}

- (void)test_select {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table = "table_a";
    auto const field_a = "field_a";
    auto const field_b = "field_b";

    XCTAssertTrue(db::create_table(db, table, {field_a, field_b}));

    db::value_vector args_1{db::value{"value_a_1"}, db::value{"value_b_1"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table, {field_a, field_b}), std::move(args_1)));

    db::value_vector args_2{db::value{"value_a_2"}, db::value{"value_b_2"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table, {field_a, field_b}), std::move(args_2)));

    auto const select_result = db::select(db, table, {.fields = {field_a, field_b},
                                                      .arguments = {std::make_pair(field_a, db::value{"value_a_2"})},
                                                      .where_exprs = db::field_expr(field_a, "=")});

    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
}

- (void)test_select_last {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector args;

    args = {db::value{1}, db::value{"value_1"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_last(db, table_name);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2");

    args = {db::value{1}, db::value{"value_1_1"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    select_result = db::select_last(db, table_name);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_1_1");
}

- (void)test_select_last_by_save_id {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_b"}, db::value{2}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_c"}, db::value{3}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_c"}, db::value{4}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    auto select_result = db::select_last(db, table_name, db::value{4});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_c");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_c");

    select_result = db::select_last(db, table_name, db::value{2});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_b");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_b");

    select_result = db::select_last(db, table_name, db::value{3});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2_b");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_1_c");

    select_result = db::select_last(db, table_name, db::value{1});
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
    std::vector<std::string> const fields{db::object_id_field, field_name, db::save_id_field};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_b"}, db::value{2}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{1}, db::value{"value_1_c"}, db::value{3}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_c"}, db::value{4}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    auto select_result =
        db::select_last(db, table_name, db::value{3}, {.field_orders = {{db::object_id_field, db::order::ascending}}});
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1_c");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2_b");

    select_result =
        db::select_last(db, table_name, db::value{3},
                        {.field_orders = {{db::object_id_field, db::order::descending}}, .limit_range = {0, 1}});
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

    db::value_vector args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}, db::value{db::insert_action}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}, db::value{db::insert_action}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}, db::value{db::update_action}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{2}, db::value{"value_2_c"}, db::value{3}, db::value{db::update_action}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_d"}, db::value{4}, db::value{db::update_action}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_d"}, db::value{4}, db::value{db::update_action}};
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

    db::value_vector args;
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

    db::value_vector args;
    args = {db::value{1}, db::value{"value_1_a"}, db::value{1}, db::value{db::insert_action}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_a"}, db::value{1}, db::value{db::insert_action}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_b"}, db::value{2}, db::value{db::update_action}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{2}, db::value{"value_2_c"}, db::value{3}, db::value{db::update_action}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    args = {db::value{1}, db::value{"value_1_d"}, db::value{4}, db::value{db::update_action}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2_d"}, db::value{4}, db::value{db::update_action}};
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

- (void)test_max {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> fields = {field_name};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    XCTAssertEqual(db::max(db, table_name, field_name), nullptr);

    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), {db::value{1}}));

    XCTAssertEqual(db::max(db, table_name, field_name), db::value{1});

    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), {db::value{10}}));

    XCTAssertEqual(db::max(db, table_name, field_name), db::value{10});

    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), {db::value{5}}));

    XCTAssertEqual(db::max(db, table_name, field_name), db::value{10});
}

- (void)test_select_in_object_ids {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector args;
    args = {db::value{1}, db::value{"value_1"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{3}, db::value{"value_3"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{4}, db::value{"value_4"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{5}, db::value{"value_5"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{6}, db::value{"value_6"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), args));

    std::set<db::integer::type> obj_ids{2, 4, 6};

    db::select_option option;
    option.where_exprs = db::object_id_field + " in (" +
                         joined(obj_ids, ",", [](auto const &obj_id) { return std::to_string(obj_id); }) + ")";
    option.field_orders = {db::field_order{db::object_id_field, db::order::ascending}};

    auto select_result = db::select(db, table_name, option);

    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 3);
    XCTAssertEqual(select_result.value().at(0).at(field_name), db::value{"value_2"});
    XCTAssertEqual(select_result.value().at(1).at(field_name), db::value{"value_4"});
    XCTAssertEqual(select_result.value().at(2).at(field_name), db::value{"value_6"});
}

- (void)test_to_object_map {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj_a0{nullptr, model, "sample_a"};
    db::object obj_a1{nullptr, model, "sample_a"};

    obj_a0.set_attribute(db::object_id_field, db::value{0});
    obj_a0.set_attribute("name", db::value{"a0"});
    obj_a1.set_attribute(db::object_id_field, db::value{1});
    obj_a1.set_attribute("name", db::value{"a1"});

    db::object_vector src_vec;
    src_vec.emplace_back(std::move(obj_a0));
    src_vec.emplace_back(std::move(obj_a1));

    XCTAssertEqual(src_vec.size(), 2);
    XCTAssertTrue(src_vec.at(0));
    XCTAssertTrue(src_vec.at(1));

    auto dst_map = to_object_map(std::move(src_vec));

    XCTAssertEqual(dst_map.size(), 2);
    XCTAssertEqual(dst_map.count(0), 1);
    XCTAssertEqual(dst_map.count(1), 1);
    XCTAssertEqual(dst_map.at(0).get_attribute("name"), db::value{"a0"});
    XCTAssertEqual(dst_map.at(1).get_attribute("name"), db::value{"a1"});

    XCTAssertEqual(src_vec.size(), 0);
}

- (void)test_to_object_map_map {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj_a0{nullptr, model, "sample_a"};
    db::object obj_a1{nullptr, model, "sample_a"};
    db::object obj_b0{nullptr, model, "sample_b"};
    db::object obj_b1{nullptr, model, "sample_b"};

    obj_a0.set_attribute(db::object_id_field, db::value{0});
    obj_a0.set_attribute("name", db::value{"a0"});
    obj_a1.set_attribute(db::object_id_field, db::value{1});
    obj_a1.set_attribute("name", db::value{"a1"});
    obj_b0.set_attribute(db::object_id_field, db::value{2});
    obj_b0.set_attribute("name", db::value{"b2"});
    obj_b1.set_attribute(db::object_id_field, db::value{3});
    obj_b1.set_attribute("name", db::value{"b3"});

    db::object_vector_map src_map;
    db::object_vector object_as;
    object_as.emplace_back(std::move(obj_a0));
    object_as.emplace_back(std::move(obj_a1));
    src_map.emplace(std::make_pair("sample_a", std::move(object_as)));
    db::object_vector object_bs;
    object_bs.emplace_back(std::move(obj_b0));
    object_bs.emplace_back(std::move(obj_b1));
    src_map.emplace(std::make_pair("sample_b", std::move(object_bs)));

    XCTAssertEqual(src_map.size(), 2);
    XCTAssertEqual(src_map.count("sample_a"), 1);
    XCTAssertEqual(src_map.count("sample_b"), 1);
    XCTAssertEqual(src_map.at("sample_a").size(), 2);
    XCTAssertEqual(src_map.at("sample_b").size(), 2);
    XCTAssertTrue(src_map.at("sample_a").at(0));
    XCTAssertTrue(src_map.at("sample_a").at(1));
    XCTAssertTrue(src_map.at("sample_b").at(0));
    XCTAssertTrue(src_map.at("sample_b").at(1));

    auto dst_map = to_object_map_map(std::move(src_map));

    XCTAssertEqual(dst_map.size(), 2);
    XCTAssertEqual(dst_map.count("sample_a"), 1);
    XCTAssertEqual(dst_map.count("sample_b"), 1);
    XCTAssertEqual(dst_map.at("sample_a").size(), 2);
    XCTAssertEqual(dst_map.at("sample_b").size(), 2);
    XCTAssertEqual(dst_map.at("sample_a").at(0).get_attribute("name"), db::value{"a0"});
    XCTAssertEqual(dst_map.at("sample_a").at(1).get_attribute("name"), db::value{"a1"});
    XCTAssertEqual(dst_map.at("sample_b").at(2).get_attribute("name"), db::value{"b2"});
    XCTAssertEqual(dst_map.at("sample_b").at(3).get_attribute("name"), db::value{"b3"});

    XCTAssertEqual(src_map.size(), 0);
    XCTAssertEqual(src_map.count("sample_a"), 0);
    XCTAssertEqual(src_map.count("sample_b"), 0);
}

- (void)test_get_const_relation_objects {
    db::model model_0_0_2{(__bridge CFDictionaryRef)[yas_db_test_utils model_dictionary_0_0_2]};
    auto manager = [yas_db_test_utils create_test_manager:std::move(model_0_0_2)];

    XCTestExpectation *exp = [self expectationWithDescription:@"1"];

    chain(std::make_pair(db::const_object{nullptr}, db::integer_set_map{}),
          {[manager](auto context) mutable {
               manager.setup([context](auto &, auto const &) mutable { context.next(); });
           },
           [manager, self](auto context) mutable {
               manager.insert_objects(
                   {{"sample_a", 2}, {"sample_b", 2}},
                   [manager, context, self](auto &, auto result) mutable {
                       XCTAssertTrue(result);

                       auto &objects = result.value();
                       objects.at("sample_a").at(0).set_attribute("name", db::value{"value_1"});
                       objects.at("sample_a")
                           .at(0)
                           .set_relation_object("child", {objects.at("sample_b").at(0), objects.at("sample_b").at(1)});
                       objects.at("sample_a").at(1).set_attribute("name", db::value{"value_2"});

                       objects.at("sample_b").at(0).set_attribute("name", db::value{"value_3"});
                       objects.at("sample_b").at(1).set_attribute("name", db::value{"value_4"});

                       manager.save([context, self](auto &, auto result) mutable {
                           XCTAssertTrue(result);
                           context.next();
                       });
                   });
           },
           [manager, self](auto context) mutable {
               manager.fetch_const_objects(
                   "sample_a", db::select_option{.where_exprs = db::equal_field_expr(db::object_id_field),
                                                 .arguments = {{db::object_id_field, db::value{1}}}},
                   [context, self](auto &manager, auto result) mutable {
                       XCTAssertTrue(result);

                       auto &objects = result.value();
                       XCTAssertEqual(objects.count("sample_a"), 1);
                       XCTAssertEqual(objects.at("sample_a").size(), 1);
                       context.set(std::make_pair(objects.at("sample_a").at(0), db::relation_ids(objects)));

                       context.next();
                   });
           },
           [manager, self, exp](auto context) mutable {
               manager.fetch_const_objects(
                   context.get().second, [context, self, exp](auto &, db::manager::const_map_result_t result) mutable {
                       XCTAssertTrue(result);

                       auto &objects = result.value();
                       XCTAssertEqual(objects.count("sample_b"), 1);
                       XCTAssertEqual(objects.at("sample_b").size(), 2);
                       XCTAssertEqual(objects.at("sample_b").count(1), 1);
                       XCTAssertEqual(objects.at("sample_b").at(1).get_attribute("name"), db::value{"value_3"});
                       XCTAssertEqual(objects.at("sample_b").count(2), 1);
                       XCTAssertEqual(objects.at("sample_b").at(2).get_attribute("name"), db::value{"value_4"});

                       db::const_object &object_a = context.get().first;
                       XCTAssertEqual(object_a.get_attribute("name"), db::value{"value_1"});
                       XCTAssertEqual(object_a.relation_size("child"), 2);
                       XCTAssertEqual(object_a.get_relation_id("child", 0), db::value{1});
                       XCTAssertEqual(object_a.get_relation_id("child", 1), db::value{2});

                       auto const_objects = db::get_const_relation_objects(object_a, objects, "child");
                       XCTAssertEqual(const_objects.size(), 2);
                       XCTAssertEqual(const_objects.at(0).get_attribute("name"), db::value{"value_3"});
                       XCTAssertEqual(const_objects.at(1).get_attribute("name"), db::value{"value_4"});

                       auto const_object_b0 = db::get_const_relation_object(object_a, objects, "child", 0);
                       XCTAssertEqual(const_object_b0.get_attribute("name"), db::value{"value_3"});

                       auto const_object_b1 = db::get_const_relation_object(object_a, objects, "child", 1);
                       XCTAssertEqual(const_object_b1.get_attribute("name"), db::value{"value_4"});

                       context.next();

                       [exp fulfill];
                   });
           }});

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

@end
