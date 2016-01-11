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

    auto map = row_set.column_map();

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

    auto map = row_set.column_map();

    XCTAssertGreaterThan(map.count("pk"), 0);
    XCTAssertGreaterThan(map.count("dflt_value"), 0);
    XCTAssertGreaterThan(map.count("type"), 0);
    XCTAssertGreaterThan(map.count("notnull"), 0);
    XCTAssertGreaterThan(map.count("name"), 0);
    XCTAssertGreaterThan(map.count("cid"), 0);

    XCTAssertEqual(map.at("name").get<db::text>(), "field_a");

    XCTAssertTrue(row_set.next());

    map = row_set.column_map();

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

    db::column_vector args_1{db::value{"value_a_1"}, db::value{"value_b_1"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table, {field_a, field_b}), std::move(args_1)));

    db::column_vector args_2{db::value{"value_a_2"}, db::value{"value_b_2"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table, {field_a, field_b}), std::move(args_2)));

    db::column_map sel_args{std::make_pair(field_a, db::value{"value_a_2"})};
    auto const select_result = db::select(db, table, {field_a, field_b}, db::field_expr(field_a, "="), sel_args);

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

    db::column_vector args;

    args = {db::value{1}, db::value{"value_1"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), std::move(args)));
    args = {db::value{2}, db::value{"value_2"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), std::move(args)));

    auto select_result = db::select_last(db, table_name);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_1");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_2");

    args = {db::value{1}, db::value{"value_1_1"}};
    XCTAssertTrue(db.execute_update(db::insert_sql(table_name, fields), std::move(args)));

    select_result = db::select_last(db, table_name);
    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 2);
    XCTAssertEqual(select_result.value().at(0).at(field_name).get<db::text>(), "value_2");
    XCTAssertEqual(select_result.value().at(1).at(field_name).get<db::text>(), "value_1_1");
}

- (void)test_max {
    db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table = "table_a";
    auto const field = "field_a";

    XCTAssertTrue(db::create_table(db, table, {field}));

    XCTAssertEqual(db::max(db, table, field), nullptr);

    XCTAssertTrue(db.execute_update(db::insert_sql(table, {field}), {db::value{1}}));

    XCTAssertEqual(db::max(db, table, field), db::value{1});

    XCTAssertTrue(db.execute_update(db::insert_sql(table, {field}), {db::value{10}}));

    XCTAssertEqual(db::max(db, table, field), db::value{10});

    XCTAssertTrue(db.execute_update(db::insert_sql(table, {field}), {db::value{5}}));

    XCTAssertEqual(db::max(db, table, field), db::value{10});
}

@end
