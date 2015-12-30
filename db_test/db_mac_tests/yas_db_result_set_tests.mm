//
//  yas_db_result_set_tests.mm
//

#import "yas_db_test_utils.h"

@interface yas_db_result_set_tests : XCTestCase

@end

@implementation yas_db_result_set_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_next_result_code {
    XCTAssertTrue(yas::db::next_result_code{SQLITE_ROW});

    XCTAssertFalse(yas::db::next_result_code{SQLITE_OK});
    XCTAssertFalse(yas::db::next_result_code{SQLITE_DONE});
    XCTAssertFalse(yas::db::next_result_code{SQLITE_ERROR});
}

- (void)test_column {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update("create table test_table (field_a, field_b);"));

    yas::db::column_map args{std::make_pair("field_a", yas::db::value{"value_a"}),
                             std::make_pair("field_b", yas::db::value{nullptr})};
    XCTAssertTrue(db.execute_update("insert into test_table(field_a, field_b) values(:field_a, :field_b)", args));

    auto query_result = db.execute_query("select field_a, field_b from test_table");
    XCTAssertTrue(query_result);

    auto &result_set = query_result.value();

    XCTAssertTrue(result_set);
    XCTAssertTrue(result_set.next());

    XCTAssertEqual(result_set.column_count(), 2);

    XCTAssertEqual(result_set.column_index("field_a").value(), 0);
    XCTAssertEqual(result_set.column_index("field_b").value(), 1);

    XCTAssertEqual(result_set.column_name(0), "field_a");
    XCTAssertEqual(result_set.column_name(1), "field_b");

    XCTAssertFalse(result_set.column_is_null(0));
    XCTAssertTrue(result_set.column_is_null(1));
    XCTAssertFalse(result_set.column_is_null("field_a"));
    XCTAssertTrue(result_set.column_is_null("field_b"));
}

- (void)test_has_row {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(db.execute_update("create table test_table (field_a, field_b);"));

    yas::db::column_map args{std::make_pair("field_a", yas::db::value{"value_a"}),
                             std::make_pair("field_b", yas::db::value{nullptr})};
    XCTAssertTrue(db.execute_update("insert into test_table(field_a, field_b) values(:field_a, :field_b)", args));

    auto query_result = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result);

    auto &result_set = query_result.value();

    XCTAssertTrue(result_set);

    XCTAssertFalse(result_set.has_row());

    XCTAssertTrue(result_set.next());

    XCTAssertTrue(result_set.has_row());

    XCTAssertFalse(result_set.next());

    XCTAssertFalse(result_set.has_row());
}

- (void)test_column_value {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(
        db.execute_update("create table test_table (int_field, float_field, string_field, data_field, null_field);"));

    std::vector<UInt8> vec{0, 1, 2, 3};

    yas::db::column_map args{std::make_pair("int_field", yas::db::value{sqlite3_int64{1}}),
                             std::make_pair("float_field", yas::db::value{Float64{2.0}}),
                             std::make_pair("string_field", yas::db::value{"string_value"}),
                             std::make_pair("data_field", yas::db::value{vec.data(), vec.size()}),
                             std::make_pair("null_field", yas::db::value{nullptr})};

    XCTAssertTrue(
        db.execute_update("insert into test_table(int_field, float_field, string_field, data_field, null_field) "
                          "values(:int_field, :float_field, :string_field, :data_field, :null_field)",
                          args));

    auto query_result = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result);

    auto &result_set = query_result.value();

    XCTAssertTrue(result_set.next());

    auto int_value = result_set.column_value("int_field");
    auto float_value = result_set.column_value("float_field");
    auto string_value = result_set.column_value("string_field");
    auto data_value = result_set.column_value("data_field");
    auto null_value = result_set.column_value("null_field");

    XCTAssertTrue(int_value.type() == typeid(yas::db::integer));
    XCTAssertTrue(float_value.type() == typeid(yas::db::real));
    XCTAssertTrue(string_value.type() == typeid(yas::db::text));
    XCTAssertTrue(data_value.type() == typeid(yas::db::blob));
    XCTAssertTrue(null_value.type() == typeid(yas::db::null));

    XCTAssertEqual(int_value.get<yas::db::integer>(), 1);
    XCTAssertEqual(float_value.get<yas::db::real>(), 2.0);
    XCTAssertEqual(string_value.get<yas::db::text>(), "string_value");

    auto &result_blob = data_value.get<yas::db::blob>();
    XCTAssertEqual(result_blob.size(), 4);

    const UInt8 *data = (const UInt8 *)result_blob.data();
    XCTAssertEqual(data[0], 0);
    XCTAssertEqual(data[1], 1);
    XCTAssertEqual(data[2], 2);
    XCTAssertEqual(data[3], 3);

    XCTAssertFalse(result_set.next());
}

- (void)test_result_map {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();

    XCTAssertTrue(
        db.execute_update("create table test_table (int_field, float_field, string_field, data_field, null_field);"));

    std::vector<UInt8> vec{0, 1, 2, 3};

    yas::db::column_map args{std::make_pair("int_field", yas::db::value{sqlite3_int64{1}}),
                             std::make_pair("float_field", yas::db::value{Float64{2.0}}),
                             std::make_pair("string_field", yas::db::value{"string_value"}),
                             std::make_pair("data_field", yas::db::value{vec.data(), vec.size()}),
                             std::make_pair("null_field", yas::db::value{nullptr})};
    XCTAssertTrue(
        db.execute_update("insert into test_table(int_field, float_field, string_field, data_field, null_field) "
                          "values(:int_field, :float_field, :string_field, :data_field, :null_field)",
                          args));

    auto query_result = db.execute_query("select * from test_table");
    XCTAssertTrue(query_result);

    auto &result_set = query_result.value();

    XCTAssertTrue(result_set.next());

    auto map = result_set.column_map();

    auto &int_value = map.at("int_field");
    auto &float_value = map.at("float_field");
    auto &string_value = map.at("string_field");
    auto &data_value = map.at("data_field");
    auto &null_value = map.at("null_field");

    XCTAssertTrue(int_value.type() == typeid(yas::db::integer));
    XCTAssertTrue(float_value.type() == typeid(yas::db::real));
    XCTAssertTrue(string_value.type() == typeid(yas::db::text));
    XCTAssertTrue(data_value.type() == typeid(yas::db::blob));
    XCTAssertTrue(null_value.type() == typeid(yas::db::null));

    XCTAssertEqual(int_value.get<yas::db::integer>(), 1);
    XCTAssertEqual(float_value.get<yas::db::real>(), 2.0);
    XCTAssertEqual(string_value.get<yas::db::text>(), "string_value");

    auto &result_blob = data_value.get<yas::db::blob>();
    XCTAssertEqual(result_blob.size(), 4);

    const UInt8 *data = (const UInt8 *)result_blob.data();
    XCTAssertEqual(data[0], 0);
    XCTAssertEqual(data[1], 1);
    XCTAssertEqual(data[2], 2);
    XCTAssertEqual(data[3], 3);

    XCTAssertFalse(result_set.next());
}

- (void)test_is_equal {
    yas::db::database db = [yas_db_test_utils create_test_database];
    db.open();
    db.execute_update("create table test_table (test_field);");

    yas::db::column_map args{std::make_pair("test_field", yas::db::value{"value"})};
    db.execute_update("insert into test_table(field_a) values(:field_a)", args);

    auto query_result = db.execute_query("select * from test_table");
    auto &result_set = query_result.value();

    yas::db::result_set null_result_set{nullptr};

    XCTAssertFalse(result_set == nullptr);
    XCTAssertTrue(result_set != nullptr);
    XCTAssertTrue(null_result_set == nullptr);
    XCTAssertFalse(null_result_set != nullptr);
}

@end
