//
//  yas_db_row_set_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_row_set_tests : XCTestCase

@end

@implementation yas_db_row_set_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [yas_db_test_utils deleteDatabase];
    [super tearDown];
}

- (void)test_next_result_code {
    XCTAssertTrue(db::next_result_code{SQLITE_ROW});

    XCTAssertFalse(db::next_result_code{SQLITE_OK});
    XCTAssertFalse(db::next_result_code{SQLITE_DONE});
    XCTAssertFalse(db::next_result_code{SQLITE_ERROR});
}

- (void)test_column {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db->execute_update("create table test_table (field_a, field_b);"));

    db::value_map_t args{std::make_pair("field_a", db::value{"value_a"}), std::make_pair("field_b", db::null_value())};
    XCTAssertTrue(db->execute_update("insert into test_table(field_a, field_b) values(:field_a, :field_b)", args));

    auto query_result = db->execute_query("select field_a, field_b from test_table");
    XCTAssertTrue(query_result);

    auto &row_set = query_result.value();

    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set->next());

    XCTAssertEqual(row_set->column_count(), 2);

    XCTAssertEqual(row_set->column_index("field_a").value(), 0);
    XCTAssertEqual(row_set->column_index("field_b").value(), 1);

    XCTAssertEqual(row_set->column_name(0), "field_a");
    XCTAssertEqual(row_set->column_name(1), "field_b");

    XCTAssertFalse(row_set->column_is_null(0));
    XCTAssertTrue(row_set->column_is_null(1));
    XCTAssertFalse(row_set->column_is_null("field_a"));
    XCTAssertTrue(row_set->column_is_null("field_b"));
}

- (void)test_has_row {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db->execute_update("create table test_table (field_a, field_b);"));

    db::value_map_t args{std::make_pair("field_a", db::value{"value_a"}), std::make_pair("field_b", db::null_value())};
    XCTAssertTrue(db->execute_update("insert into test_table(field_a, field_b) values(:field_a, :field_b)", args));

    auto query_result = db->execute_query("select * from test_table");
    XCTAssertTrue(query_result);

    auto &row_set = query_result.value();

    XCTAssertTrue(row_set);

    XCTAssertFalse(row_set->has_row());

    XCTAssertTrue(row_set->next());

    XCTAssertTrue(row_set->has_row());

    XCTAssertFalse(row_set->next());

    XCTAssertFalse(row_set->has_row());
}

- (void)test_column_value {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(
        db->execute_update("create table test_table (int_field, float_field, string_field, data_field, null_field);"));

    std::vector<uint8_t> vec{0, 1, 2, 3};

    db::value_map_t args{std::make_pair("int_field", db::value{sqlite3_int64{1}}),
                         std::make_pair("float_field", db::value{double{2.0}}),
                         std::make_pair("string_field", db::value{"string_value"}),
                         std::make_pair("data_field", db::value{vec.data(), vec.size()}),
                         std::make_pair("null_field", db::null_value())};

    XCTAssertTrue(
        db->execute_update("insert into test_table(int_field, float_field, string_field, data_field, null_field) "
                          "values(:int_field, :float_field, :string_field, :data_field, :null_field)",
                          args));

    auto query_result = db->execute_query("select * from test_table");
    XCTAssertTrue(query_result);

    auto &row_set = query_result.value();

    XCTAssertTrue(row_set->next());

    auto int_value = row_set->column_value("int_field");
    auto float_value = row_set->column_value("float_field");
    auto string_value = row_set->column_value("string_field");
    auto data_value = row_set->column_value("data_field");
    auto null_value = row_set->column_value("null_field");

    XCTAssertTrue(int_value.type() == typeid(db::integer));
    XCTAssertTrue(float_value.type() == typeid(db::real));
    XCTAssertTrue(string_value.type() == typeid(db::text));
    XCTAssertTrue(data_value.type() == typeid(db::blob));
    XCTAssertTrue(null_value.type() == typeid(db::null));

    XCTAssertEqual(int_value.get<db::integer>(), 1);
    XCTAssertEqual(float_value.get<db::real>(), 2.0);
    XCTAssertEqual(string_value.get<db::text>(), "string_value");

    auto &result_blob = data_value.get<db::blob>();
    XCTAssertEqual(result_blob.size(), 4);

    const uint8_t *data = (const uint8_t *)result_blob.data();
    XCTAssertEqual(data[0], 0);
    XCTAssertEqual(data[1], 1);
    XCTAssertEqual(data[2], 2);
    XCTAssertEqual(data[3], 3);

    XCTAssertFalse(row_set->next());
}

- (void)test_result_map {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(
        db->execute_update("create table test_table (int_field, float_field, string_field, data_field, null_field);"));

    std::vector<uint8_t> vec{0, 1, 2, 3};

    db::value_map_t args{std::make_pair("int_field", db::value{sqlite3_int64{1}}),
                         std::make_pair("float_field", db::value{double{2.0}}),
                         std::make_pair("string_field", db::value{"string_value"}),
                         std::make_pair("data_field", db::value{vec.data(), vec.size()}),
                         std::make_pair("null_field", db::null_value())};
    XCTAssertTrue(
        db->execute_update("insert into test_table(int_field, float_field, string_field, data_field, null_field) "
                          "values(:int_field, :float_field, :string_field, :data_field, :null_field)",
                          args));

    auto query_result = db->execute_query("select * from test_table");
    XCTAssertTrue(query_result);

    auto &row_set = query_result.value();

    XCTAssertTrue(row_set->next());

    auto map = row_set->values();

    auto &int_value = map.at("int_field");
    auto &float_value = map.at("float_field");
    auto &string_value = map.at("string_field");
    auto &data_value = map.at("data_field");
    auto &null_value = map.at("null_field");

    XCTAssertTrue(int_value.type() == typeid(db::integer));
    XCTAssertTrue(float_value.type() == typeid(db::real));
    XCTAssertTrue(string_value.type() == typeid(db::text));
    XCTAssertTrue(data_value.type() == typeid(db::blob));
    XCTAssertTrue(null_value.type() == typeid(db::null));

    XCTAssertEqual(int_value.get<db::integer>(), 1);
    XCTAssertEqual(float_value.get<db::real>(), 2.0);
    XCTAssertEqual(string_value.get<db::text>(), "string_value");

    auto &result_blob = data_value.get<db::blob>();
    XCTAssertEqual(result_blob.size(), 4);

    const uint8_t *data = (const uint8_t *)result_blob.data();
    XCTAssertEqual(data[0], 0);
    XCTAssertEqual(data[1], 1);
    XCTAssertEqual(data[2], 2);
    XCTAssertEqual(data[3], 3);

    XCTAssertFalse(row_set->next());
}

- (void)test_is_equal {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());
    db->execute_update("create table test_table (test_field);");

    db::value_map_t args{std::make_pair("test_field", db::value{"value"})};
    db->execute_update("insert into test_table(field_a) values(:field_a)", args);

    auto query_result = db->execute_query("select * from test_table");
    auto &row_set = query_result.value();

    XCTAssertFalse(row_set == nullptr);
    XCTAssertTrue(row_set != nullptr);
}

@end
