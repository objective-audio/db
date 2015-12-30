//
//  yas_db_database_tests.mm
//

#import <XCTest/XCTest.h>
#import "yas_db_test_utils.h"

#import <array>
#import <list>

@interface yas_db_database_tests : XCTestCase

@end

@implementation yas_db_database_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_sqlite_info {
    XCTAssertGreaterThan(yas::db::database::sqlite_lib_version().size(), 0);
    XCTAssertTrue(yas::db::database::sqlite_thread_safe());
}

- (void)test_sqlite_result_code {
    XCTAssertTrue(yas::db::sqlite_result_code(SQLITE_OK));
    XCTAssertTrue(yas::db::sqlite_result_code{SQLITE_DONE});

    XCTAssertFalse(yas::db::sqlite_result_code(SQLITE_ROW));
    XCTAssertFalse(yas::db::sqlite_result_code{SQLITE_ERROR});
}

- (void)test_create {
    NSString *databasePath = [yas_db_test_utils databasePath];
    std::string db_path = yas::to_string((__bridge CFStringRef)databasePath);
    XCTAssertGreaterThan(db_path.size(), 0);

    yas::db::database db{db_path};

    XCTAssertEqual(db.database_path(), db_path);
    XCTAssertTrue(db.sqlite_handle() == nullptr);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:databasePath]);
}

- (void)test_open_and_close {
    yas::db::database db = [yas_db_test_utils create_test_database];
    NSString *databasePath = [yas_db_test_utils databasePath];

    XCTAssertFalse(db.good_connection());

    db.open();

    XCTAssertTrue(db.sqlite_handle() != nullptr);
    XCTAssertTrue(db.good_connection());
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:databasePath]);

    db.close();

    XCTAssertTrue(db.sqlite_handle() == nullptr);
    XCTAssertFalse(db.good_connection());
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:databasePath]);
}

- (void)test_table_exists {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"field"})));

    XCTAssertTrue(db.table_exists("test_table"));
    XCTAssertFalse(db.table_exists("hoge"));
}

- (void)test_column_exists {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"field_a", "field_b"})));

    XCTAssertTrue(db.column_exists("field_a", "test_table"));
    XCTAssertTrue(db.column_exists("field_b", "test_table"));

    XCTAssertFalse(db.column_exists("field_a", "hoge"));
    XCTAssertFalse(db.column_exists("hage", "test_table"));
}

- (void)test_create_table {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update("create table test_table_1 (field_a, field_b);"));
    XCTAssertTrue(db.execute_update("create table test_table_2 (field_c, field_d);"));

    XCTAssertTrue(db.table_exists("test_table_1"));
    XCTAssertTrue(db.column_exists("field_a", "test_table_1"));
    XCTAssertTrue(db.column_exists("field_b", "test_table_1"));
    XCTAssertTrue(db.table_exists("test_table_2"));
    XCTAssertTrue(db.column_exists("field_c", "test_table_2"));
    XCTAssertTrue(db.column_exists("field_d", "test_table_2"));
}

- (void)test_execute_update_with_vector {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"field_a", "field_b"})));

    yas::db::column_vector arguments;
    arguments.emplace_back(yas::db::column_value{"value_a"});
    arguments.emplace_back(yas::db::column_value{"value_b"});
    XCTAssertTrue(db.execute_update("insert into test_table(field_a, field_b) values(:field_a, :field_b)", arguments));

    auto query_result = db.execute_query("select * from test_table");
    auto &result_set = query_result.value();

    XCTAssertTrue(result_set);
    XCTAssertTrue(result_set.next());

    XCTAssertEqual(result_set.column_value(0).value<yas::db::text>(), "value_a");
    XCTAssertEqual(result_set.column_value(1).value<yas::db::text>(), "value_b");

    XCTAssertFalse(result_set.next());
}

- (void)test_execute_update_with_map {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"field_a", "field_b"})));

    yas::db::column_map arguments;
    arguments.emplace(std::make_pair("field_a", yas::db::column_value{"value_a"}));
    arguments.emplace(std::make_pair("field_b", yas::db::column_value{"value_b"}));
    XCTAssertTrue(db.execute_update("insert into test_table(field_a, field_b) values(:field_a, :field_b)", arguments));

    auto query_result = db.execute_query("select * from test_table");
    auto &result_set = query_result.value();

    XCTAssertTrue(result_set);
    XCTAssertTrue(result_set.next());

    XCTAssertEqual(result_set.column_value("field_a").value<yas::db::text>(), "value_a");
    XCTAssertEqual(result_set.column_value("field_b").value<yas::db::text>(), "value_b");

    XCTAssertFalse(result_set.next());
}

- (void)test_execute_query_with_vector {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"field_a"})));

    yas::db::column_vector args_1;
    args_1.emplace_back(yas::db::column_value{"value_a"});
    XCTAssertTrue(db.execute_update("insert into test_table(field_a) values(:field_a)", args_1));

    yas::db::column_vector args_2;
    args_2.emplace_back(yas::db::column_value{"hoge_a"});
    XCTAssertTrue(db.execute_update("insert into test_table(field_a) values(:field_a)", args_2));

    yas::db::column_vector query_arguments;
    query_arguments.emplace_back(yas::db::column_value{"value_a"});
    auto query_result = db.execute_query("select * from test_table where field_a = :field_a", query_arguments);

    XCTAssertTrue(query_result);

    auto &result_set = query_result.value();

    XCTAssertTrue(result_set);
    XCTAssertTrue(result_set.next());

    XCTAssertEqual(result_set.column_value("field_a").value<yas::db::text>(), "value_a");

    XCTAssertFalse(result_set.next());
}

- (void)test_execute_query_with_map {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"field_a"})));

    yas::db::column_vector args_1;
    args_1.emplace_back(yas::db::column_value{"value_a"});
    XCTAssertTrue(db.execute_update("insert into test_table(field_a) values(:field_a)", args_1));

    yas::db::column_vector args_2;
    args_2.emplace_back(yas::db::column_value{"hoge_a"});
    XCTAssertTrue(db.execute_update("insert into test_table(field_a) values(:field_a)", args_2));

    yas::db::column_map query_arguments;
    query_arguments.emplace(std::make_pair("field_a", yas::db::column_value{"value_a"}));
    auto query_result = db.execute_query("select * from test_table where field_a = :field_a", query_arguments);

    XCTAssertTrue(query_result);

    auto &result_set = query_result.value();

    XCTAssertTrue(result_set);
    XCTAssertTrue(result_set.next());

    XCTAssertEqual(result_set.column_value("field_a").value<yas::db::text>(), "value_a");

    XCTAssertFalse(result_set.next());
}

- (void)test_transaction_commit {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"test_field"})));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));

    auto query_result_1 = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result_1);
    XCTAssertTrue(query_result_1.value().next());
    XCTAssertFalse(query_result_1.value().next());

    XCTAssertFalse(db.in_transaction());

    XCTAssertTrue(db.begin_transaction());
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value2')"));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value3')"));
    XCTAssertTrue(db.in_transaction());
    XCTAssertTrue(db.commit());

    XCTAssertFalse(db.in_transaction());

    auto query_result_2 = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result_2);
    XCTAssertTrue(query_result_2.value().next());
    XCTAssertTrue(query_result_2.value().next());
    XCTAssertTrue(query_result_2.value().next());
    XCTAssertFalse(query_result_2.value().next());
}

- (void)test_transaction_rollback {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"test_field"})));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));

    auto query_result_1 = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result_1);
    XCTAssertTrue(query_result_1.value().next());
    XCTAssertFalse(query_result_1.value().next());

    XCTAssertTrue(db.begin_transaction());
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value2')"));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value3')"));
    XCTAssertTrue(db.rollback());

    auto query_result_2 = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result_2);
    XCTAssertTrue(query_result_2.value().next());
    XCTAssertFalse(query_result_2.value().next());
}

- (void)test_save_point {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"test_field"})));

    auto count_of_row = [&db]() {
        auto query_result = db.execute_query("select * from test_table");
        int count = 0;
        while (query_result.value().next()) {
            ++count;
        }
        return count;
    };

    XCTAssertEqual(count_of_row(), 0);
    XCTAssertTrue(db.start_save_point("sp_1"));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));
    XCTAssertEqual(count_of_row(), 1);
    XCTAssertTrue(db.start_save_point("sp_2"));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value2')"));
    XCTAssertEqual(count_of_row(), 2);
    XCTAssertTrue(db.rollback_save_point("sp_2"));
    XCTAssertEqual(count_of_row(), 1);
    XCTAssertTrue(db.release_save_point("sp_1"));
    XCTAssertEqual(count_of_row(), 1);
}

- (void)test_in_save_point {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"test_field"})));

    auto count_of_row = [&db]() {
        auto query_result = db.execute_query("select * from test_table");
        int count = 0;
        while (query_result.value().next()) {
            ++count;
        }
        return count;
    };

    XCTAssertTrue(db.in_save_point([&db, &count_of_row, &self](bool &should_rollback) {
        XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));
        XCTAssertEqual(count_of_row(), 1);
    }));

    XCTAssertEqual(count_of_row(), 1);
}

- (void)test_in_save_point_rollback {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"test_field"})));

    auto count_of_row = [&db]() {
        auto query_result = db.execute_query("select * from test_table");
        int count = 0;
        while (query_result.value().next()) {
            ++count;
        }
        return count;
    };

    XCTAssertTrue(db.in_save_point([&db, &count_of_row, &self](bool &should_rollback) {
        XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));
        XCTAssertEqual(count_of_row(), 1);
        should_rollback = true;
    }));

    XCTAssertEqual(count_of_row(), 0);
}

- (void)test_savepoint_failed {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertFalse(db.start_save_point(""));
    XCTAssertFalse(db.release_save_point(""));
    XCTAssertFalse(db.rollback_save_point(""));
}

- (void)test_get_error {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertFalse(db.had_error());
    XCTAssertEqual(db.last_error_code(), SQLITE_OK);
    XCTAssertEqual(db.last_error_message(), "not an error");

    XCTAssertFalse(db.execute_update("hoge"));

    XCTAssertTrue(db.had_error());
    XCTAssertNotEqual(db.last_error_code(), SQLITE_OK);
    XCTAssertNotEqual(db.last_error_message(), "not an error");
}

- (void)test_should_cache_statement {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();
    db.set_should_cache_statements(true);

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"test_field"})));

    std::string insert_query = "insert into test_table(test_field) values('value1')";
    std::string select_query = "select * from test_table";

    XCTAssertTrue(db.execute_update(insert_query));

    auto query_result_1 = db.execute_query(select_query);
    XCTAssertTrue(query_result_1);
    XCTAssertTrue(query_result_1.value().next());
    XCTAssertFalse(query_result_1.value().next());

    XCTAssertTrue(db.execute_update(insert_query));

    auto query_result_2 = db.execute_query(select_query);
    XCTAssertTrue(query_result_2);
    XCTAssertTrue(query_result_2.value().next());
    XCTAssertTrue(query_result_2.value().next());
    XCTAssertFalse(query_result_2.value().next());

    XCTAssertEqual(query_result_1.value().statement(), query_result_2.value().statement());

    db.set_should_cache_statements(false);

    auto query_result_3 = db.execute_query(select_query);

    XCTAssertNotEqual(query_result_1.value().statement(), query_result_3.value().statement());
}

- (void)test_open_result_sets {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update(yas::db::create_table_sql("test_table", {"test_field"})));
    XCTAssertTrue(db.execute_update("insert into test_table(test_field) values('value1')"));

    XCTAssertFalse(db.has_open_result_sets());

    if (auto query_result = db.execute_query("select * from test_table")) {
        XCTAssertTrue(db.has_open_result_sets());
    }

    XCTAssertFalse(db.has_open_result_sets());

    if (auto query_result = db.execute_query("select * from test_table")) {
        auto &result_set = query_result.value();
        XCTAssertTrue(result_set.next());
        XCTAssertTrue(result_set.has_row());
        XCTAssertTrue(db.has_open_result_sets());

        db.close_open_result_sets();

        XCTAssertFalse(result_set.has_row());
        XCTAssertFalse(db.has_open_result_sets());
    }
}

- (void)test_get_schema {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    std::string const sql = "create table test_table (test_field)";
    XCTAssertTrue(db.execute_update(sql));

    auto result_set = db.get_schema();
    XCTAssertTrue(result_set);
    XCTAssertTrue(result_set.next());

    auto map = result_set.column_map();

    XCTAssertGreaterThan(map.count("sql"), 0);
    auto &sql_column_value = map.at("sql");
    XCTAssertTrue(sql_column_value.type() == typeid(yas::db::text));
    XCTAssertEqual(yas::to_lower(sql_column_value.value<yas::db::text>()), sql);

    XCTAssertGreaterThan(map.count("tbl_name"), 0);
    auto &tbl_name_column_value = map.at("tbl_name");
    XCTAssertTrue(tbl_name_column_value.type() == typeid(yas::db::text));
    XCTAssertEqual(tbl_name_column_value.value<yas::db::text>(), "test_table");

    XCTAssertGreaterThan(map.count("name"), 0);
    auto &name_column_value = map.at("name");
    XCTAssertTrue(name_column_value.type() == typeid(yas::db::text));
    XCTAssertEqual(name_column_value.value<yas::db::text>(), "test_table");

    XCTAssertGreaterThan(map.count("rootpage"), 0);
    auto &rootpage_column_value = map.at("rootpage");
    XCTAssertTrue(rootpage_column_value.type() == typeid(yas::db::integer));
    XCTAssertEqual(sql_column_value.value<yas::db::integer>(), 0);

    XCTAssertGreaterThan(map.count("type"), 0);
    auto &type_column_value = map.at("type");
    XCTAssertTrue(type_column_value.type() == typeid(yas::db::text));
    XCTAssertEqual(type_column_value.value<yas::db::text>(), "table");

    XCTAssertFalse(result_set.next());
}

- (void)test_get_table_schema {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    std::string const sql = yas::db::create_table_sql("test_table", {"field_a", "field_b"});
    XCTAssertTrue(db.execute_update(sql));

    auto result_set = db.get_table_schema("test_table");
    XCTAssertTrue(result_set);
    XCTAssertTrue(result_set.next());

    auto map = result_set.column_map();

    XCTAssertGreaterThan(map.count("pk"), 0);
    XCTAssertGreaterThan(map.count("dflt_value"), 0);
    XCTAssertGreaterThan(map.count("type"), 0);
    XCTAssertGreaterThan(map.count("notnull"), 0);
    XCTAssertGreaterThan(map.count("name"), 0);
    XCTAssertGreaterThan(map.count("cid"), 0);

    XCTAssertEqual(map.at("name").value<yas::db::text>(), "field_a");

    for (auto &pair : map) {
        auto &column_value = pair.second;
        std::cout << pair.first << " _ " << yas::to_string(column_value) << std::endl;
    }

    XCTAssertTrue(result_set.next());

    map = result_set.column_map();

    XCTAssertEqual(map.at("name").value<yas::db::text>(), "field_b");

    XCTAssertFalse(result_set.next());
}

- (void)test_max_busy_retry_time_interval {
    yas::db::database db = [yas_db_test_utils create_test_database];

    db.set_max_busy_retry_time_interval(10.0);
    XCTAssertEqual(db.max_busy_retry_time_interval(), 10.0);
}

- (void)test_start_busy_retry_time {
    yas::db::database db = [yas_db_test_utils create_test_database];

    auto now = std::chrono::system_clock::now();
    db.set_start_busy_retry_time(now);
    XCTAssertEqual(db.start_busy_retry_time(), now);
}

- (void)test_table {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.create_table("test_table_a", {"field_a"}));
    XCTAssertTrue(db.create_table("test_table_b", {"field_b"}));

    XCTAssertTrue(db.table_exists("test_table_a"));
    XCTAssertTrue(db.table_exists("test_table_b"));

    auto schema_set_1 = db.get_table_schema("test_table_a");
    XCTAssertTrue(schema_set_1.next());
    XCTAssertEqual(schema_set_1.column_value("name").value<yas::db::text>(), "field_a");
    XCTAssertFalse(schema_set_1.next());

    XCTAssertTrue(db.alter_table("test_table_a", "field_c"));

    auto schema_set_2 = db.get_table_schema("test_table_a");
    XCTAssertTrue(schema_set_2.next());
    XCTAssertEqual(schema_set_2.column_value("name").value<yas::db::text>(), "field_a");
    XCTAssertTrue(schema_set_2.next());
    XCTAssertEqual(schema_set_2.column_value("name").value<yas::db::text>(), "field_c");
    XCTAssertFalse(schema_set_2.next());

    XCTAssertTrue(db.drop_table("test_table_b"));

    XCTAssertTrue(db.table_exists("test_table_a"));
    XCTAssertFalse(db.table_exists("test_table_b"));
}

- (void)test_select {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    auto const table = "table_a";
    auto const field_a = "field_a";
    auto const field_b = "field_b";

    XCTAssertTrue(db.create_table(table, {field_a, field_b}));

    yas::db::column_vector args_1;
    args_1.emplace_back(yas::db::column_value{"value_a_1"});
    args_1.emplace_back(yas::db::column_value{"value_b_1"});

    XCTAssertTrue(db.execute_update(yas::db::insert_sql(table, {field_a, field_b}), std::move(args_1)));

    yas::db::column_vector args_2;
    args_2.emplace_back(yas::db::column_value{"value_a_2"});
    args_2.emplace_back(yas::db::column_value{"value_b_2"});

    XCTAssertTrue(db.execute_update(yas::db::insert_sql(table, {field_a, field_b}), std::move(args_2)));

    yas::db::column_map param_map;
    param_map.emplace(std::make_pair(field_a, yas::db::column_value{"value_a_2"}));
    std::vector<yas::db::column_map> param_maps;
    param_maps.emplace_back(std::move(param_map));

    auto result_map =
        db.select(table, {field_a, field_b}, yas::db::and_exprs({yas::db::equal_expr(field_a)}), param_maps);

    XCTAssertEqual(result_map.size(), 1);
}

@end
