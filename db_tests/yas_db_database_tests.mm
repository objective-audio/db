//
//  yas_db_database_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_database_tests : XCTestCase

@end

@implementation yas_db_database_tests

- (void)setUp {
    [super setUp];
    [yas_db_test_utils deleteDatabase];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_sqlite_info {
    XCTAssertGreaterThan(db::database::sqlite_lib_version().size(), 0);
    XCTAssertTrue(db::database::sqlite_thread_safe());
}

- (void)test_sqlite_result_code {
    XCTAssertTrue(db::sqlite_result_code(SQLITE_OK));
    XCTAssertTrue(db::sqlite_result_code{SQLITE_DONE});

    XCTAssertFalse(db::sqlite_result_code(SQLITE_ROW));
    XCTAssertFalse(db::sqlite_result_code{SQLITE_ERROR});
}

- (void)test_create {
    NSString *databasePath = [yas_db_test_utils databasePath];
    std::string db_path = yas::to_string((__bridge CFStringRef)databasePath);
    XCTAssertGreaterThan(db_path.size(), 0);

    db::database_ptr const db = db::database::make_shared(db_path);

    XCTAssertEqual(db->database_path(), db_path);
    XCTAssertTrue(db->sqlite_handle() == nullptr);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:databasePath]);
}

- (void)test_open_and_close {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    NSString *databasePath = [yas_db_test_utils databasePath];

    XCTAssertFalse(db->good_connection());

    XCTAssertTrue(db->open());

    XCTAssertTrue(db->sqlite_handle() != nullptr);
    XCTAssertTrue(db->good_connection());
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:databasePath]);

    db->close();

    XCTAssertTrue(db->sqlite_handle() == nullptr);
    XCTAssertFalse(db->good_connection());
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:databasePath]);
}

- (void)test_create_table {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db->execute_update("create table test_table_1 (field_a, field_b);"));
    XCTAssertTrue(db->execute_update("create table test_table_2 (field_c, field_d);"));

    XCTAssertTrue(db::table_exists(db, "test_table_1"));
    XCTAssertTrue(db::column_exists(db, "field_a", "test_table_1"));
    XCTAssertTrue(db::column_exists(db, "field_b", "test_table_1"));
    XCTAssertTrue(db::table_exists(db, "test_table_2"));
    XCTAssertTrue(db::column_exists(db, "field_c", "test_table_2"));
    XCTAssertTrue(db::column_exists(db, "field_d", "test_table_2"));
}

- (void)test_execute_update_with_vector {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"field_a", "field_b"}));

    db::value_vector_t args{db::value{"value_a"}, db::value{"value_b"}};
    XCTAssertTrue(db->execute_update("insert into test_table(field_a, field_b) values(:field_a, :field_b)", args));

    auto query_result = db->execute_query("select * from test_table");
    auto &row_set = query_result.value();

    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set->next());

    XCTAssertEqual(row_set->column_value(0).get<db::text>(), "value_a");
    XCTAssertEqual(row_set->column_value(1).get<db::text>(), "value_b");

    XCTAssertFalse(row_set->next());

    db::value_vector_t update_args{db::value{"value_a_2"}, db::value{"value_b_2"}};
    XCTAssertTrue(db->execute_update("update test_table set field_a = :field_a, field_b = :field_b", update_args));

    query_result = db->execute_query("select * from test_table");
    row_set = query_result.value();

    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set->next());

    XCTAssertEqual(row_set->column_value(0).get<db::text>(), "value_a_2");
    XCTAssertEqual(row_set->column_value(1).get<db::text>(), "value_b_2");

    XCTAssertFalse(row_set->next());
}

- (void)test_execute_update_with_map {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"field_a", "field_b"}));

    db::value_map_t args{std::make_pair("field_a", db::value{"value_a"}),
                         std::make_pair("field_b", db::value{"value_b"})};
    XCTAssertTrue(db->execute_update("insert into test_table(field_a, field_b) values(:field_a, :field_b)", args));

    auto query_result = db->execute_query("select * from test_table");
    auto &row_set = query_result.value();

    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set->next());

    XCTAssertEqual(row_set->column_value("field_a").get<db::text>(), "value_a");
    XCTAssertEqual(row_set->column_value("field_b").get<db::text>(), "value_b");

    XCTAssertFalse(row_set->next());

    db::value_map_t update_args{std::make_pair("field_a", db::value{"value_a_2"}),
                                std::make_pair("field_b", db::value{"value_b_2"})};
    XCTAssertTrue(db->execute_update("update test_table set field_a = :field_a, field_b = :field_b", update_args));

    query_result = db->execute_query("select * from test_table");
    row_set = query_result.value();

    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set->next());

    XCTAssertEqual(row_set->column_value(0).get<db::text>(), "value_a_2");
    XCTAssertEqual(row_set->column_value(1).get<db::text>(), "value_b_2");

    XCTAssertFalse(row_set->next());
}

- (void)test_execute_statements {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    std::string sql_a = db::create_table_sql("test_table_a", {"field_a", "field_b"});
    std::string sql_b = db::create_table_sql("test_table_b", {"field_a", "field_b"});
    auto joined_sql = joined({sql_a, sql_b}, "");

    XCTAssertTrue(db->execute_statements(joined_sql));

    XCTAssertTrue(db::table_exists(db, "test_table_a"));
    XCTAssertTrue(db::table_exists(db, "test_table_b"));

    std::string insert_a = "insert into test_table_a(field_a, field_b) values('value_1', 1);";
    std::string insert_b = "insert into test_table_b(field_a, field_b) values('value_2', null);";
    std::string joined_insert_sql = joined({insert_a, insert_b}, "");

    XCTAssertTrue(db->execute_statements(joined_insert_sql));

    XCTAssertTrue(db->execute_statements({"select * from test_table_a;"}, [](db::value_map_t const &value_map) {
        XCTAssertEqual(value_map.size(), 2);
        XCTAssertEqual(value_map.at("field_a").get<db::text>(), "value_1");
        XCTAssertEqual(value_map.at("field_b").get<db::text>(), "1");
        return 0;
    }));

    XCTAssertTrue(db->execute_statements({"select * from test_table_b;"}, [](db::value_map_t const &value_map) {
        XCTAssertEqual(value_map.size(), 2);
        XCTAssertEqual(value_map.at("field_a").get<db::text>(), "value_2");
        XCTAssertTrue(value_map.at("field_b").type() == typeid(db::null));
        return 0;
    }));
}

- (void)test_execute_query_with_vector {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"field_a"}));

    XCTAssertTrue(db->execute_update("insert into test_table(field_a) values(:field_a)", {db::value{"value_a"}}));

    XCTAssertTrue(db->execute_update("insert into test_table(field_a) values(:field_a)", {db::value{"hoge_a"}}));

    auto query_result = db->execute_query("select * from test_table where field_a = :field_a", {db::value{"value_a"}});

    XCTAssertTrue(query_result);

    auto const &row_set = query_result.value();

    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set->next());

    XCTAssertEqual(row_set->column_value("field_a").get<db::text>(), "value_a");

    XCTAssertFalse(row_set->next());
}

- (void)test_execute_query_with_map {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"field_a"}));

    XCTAssertTrue(db->execute_update("insert into test_table(field_a) values(:field_a)", {db::value{"value_a"}}));

    XCTAssertTrue(db->execute_update("insert into test_table(field_a) values(:field_a)", {db::value{"hoge_a"}}));

    auto query_result = db->execute_query("select * from test_table where field_a = :field_a",
                                          {std::make_pair("field_a", db::value{"value_a"})});

    XCTAssertTrue(query_result);

    auto &row_set = query_result.value();

    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set->next());

    XCTAssertEqual(row_set->column_value("field_a").get<db::text>(), "value_a");

    XCTAssertFalse(row_set->next());
}

- (void)test_get_error {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertFalse(db->had_error());
    XCTAssertEqual(db->last_error_code(), SQLITE_OK);
    XCTAssertEqual(db->last_error_message(), "not an error");

    XCTAssertFalse(db->execute_update("hoge"));

    XCTAssertTrue(db->had_error());
    XCTAssertNotEqual(db->last_error_code(), SQLITE_OK);
    XCTAssertNotEqual(db->last_error_message(), "not an error");
}

- (void)test_should_cache_statement {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());
    db->set_should_cache_statements(true);

    XCTAssertTrue(db::create_table(db, "test_table", {"test_field"}));

    std::string insert_query = "insert into test_table(test_field) values('value1')";
    std::string select_query = "select * from test_table";

    XCTAssertTrue(db->execute_update(insert_query));

    auto query_result_1 = db->execute_query(select_query);
    XCTAssertTrue(query_result_1);
    XCTAssertTrue(query_result_1.value()->next());
    XCTAssertFalse(query_result_1.value()->next());

    XCTAssertTrue(db->execute_update(insert_query));

    auto query_result_2 = db->execute_query(select_query);
    XCTAssertTrue(query_result_2);
    XCTAssertTrue(query_result_2.value()->next());
    XCTAssertTrue(query_result_2.value()->next());
    XCTAssertFalse(query_result_2.value()->next());

    XCTAssertEqual(query_result_1.value()->statement(), query_result_2.value()->statement());

    db->set_should_cache_statements(false);

    auto query_result_3 = db->execute_query(select_query);

    XCTAssertNotEqual(query_result_1.value()->statement(), query_result_3.value()->statement());
}

- (void)test_open_row_sets {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"test_field"}));
    XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value1')"));

    XCTAssertFalse(db->has_opened_row_sets());

    if (auto query_result = db->execute_query("select * from test_table")) {
        XCTAssertTrue(db->has_opened_row_sets());
    }

    XCTAssertFalse(db->has_opened_row_sets());

    if (auto query_result = db->execute_query("select * from test_table")) {
        auto &row_set = query_result.value();
        XCTAssertTrue(row_set->next());
        XCTAssertTrue(row_set->has_row());
        XCTAssertTrue(db->has_opened_row_sets());

        db->close_opened_row_sets();

        XCTAssertFalse(row_set->has_row());
        XCTAssertFalse(db->has_opened_row_sets());
    }
}

- (void)test_max_busy_retry_time_interval {
    db::database_ptr const db = [yas_db_test_utils create_test_database];

    db->set_max_busy_retry_time_interval(10.0);
    XCTAssertEqual(db->max_busy_retry_time_interval(), 10.0);
}

- (void)test_start_busy_retry_time {
    db::database_ptr const db = [yas_db_test_utils create_test_database];

    auto now = std::chrono::system_clock::now();
    db->set_start_busy_retry_time(now);
    XCTAssertEqual(db->start_busy_retry_time(), now);
}

- (void)test_foreign_key {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    db::begin_transaction(db);

    XCTAssertTrue(db->execute_update("create table idmaster (id integer primary key autoincrement, name text);"));
    XCTAssertTrue(db->execute_update("insert into idmaster values (null, 'A');"));
    XCTAssertTrue(db->execute_update(
        "create table address (id integer, address text, foreign key(id) references idmaster(id) on delete cascade);"));
    XCTAssertTrue(db->execute_update("insert into address values (1, 'addressA');"));
    XCTAssertFalse(db->execute_update("insert into address values (2, 'addressB');"));

    db::commit(db);

    auto query_result = db->execute_query("select * from idmaster;");
    auto &row_set = query_result.value();
    XCTAssertTrue(row_set->next());
    XCTAssertFalse(row_set->next());

    query_result = db->execute_query("select * from address;");
    row_set = query_result.value();
    XCTAssertTrue(row_set->next());
    XCTAssertFalse(row_set->next());

    XCTAssertTrue(db->execute_update("delete from idmaster"));

    query_result = db->execute_query("select * from idmaster;");
    row_set = query_result.value();
    XCTAssertFalse(row_set->next());

    query_result = db->execute_query("select * from address;");
    row_set = query_result.value();
    XCTAssertFalse(row_set->next());
}

- (void)test_integrity_check {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    auto result = db->integrity_check();
    XCTAssertTrue(result.is_success());
}

- (void)test_error_type_to_string {
    XCTAssertEqual(to_string(db::error_type::closed), "closed");
    XCTAssertEqual(to_string(db::error_type::in_use), "in_use");
    XCTAssertEqual(to_string(db::error_type::invalid_query_count), "invalid_query_count");
    XCTAssertEqual(to_string(db::error_type::invalid_argument), "invalid_argument");
    XCTAssertEqual(to_string(db::error_type::sqlite), "sqlite");
    XCTAssertEqual(to_string(db::error_type::none), "none");
}

@end
