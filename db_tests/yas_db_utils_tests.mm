//
//  yas_db_utils_tests.mm
//

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
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table_a", {"field_a"}));
    XCTAssertTrue(db::create_table(db, "test_table_b", {"field_b"}));

    XCTAssertTrue(db::table_exists(db, "test_table_a"));
    XCTAssertTrue(db::table_exists(db, "test_table_b"));

    auto schema_set_1 = db::get_table_schema(db, "test_table_a");
    XCTAssertTrue(schema_set_1->next());
    XCTAssertEqual(schema_set_1->column_value("name").get<db::text>(), "field_a");
    XCTAssertFalse(schema_set_1->next());

    XCTAssertTrue(db::alter_table(db, "test_table_a", "field_c"));

    auto schema_set_2 = db::get_table_schema(db, "test_table_a");
    XCTAssertTrue(schema_set_2->next());
    XCTAssertEqual(schema_set_2->column_value("name").get<db::text>(), "field_a");
    XCTAssertTrue(schema_set_2->next());
    XCTAssertEqual(schema_set_2->column_value("name").get<db::text>(), "field_c");
    XCTAssertFalse(schema_set_2->next());

    XCTAssertTrue(db::drop_table(db, "test_table_b"));

    XCTAssertTrue(db::table_exists(db, "test_table_a"));
    XCTAssertFalse(db::table_exists(db, "test_table_b"));
}

- (void)test_transaction_commit {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db->execute_update(db::create_table_sql("test_table", {"test_field"})));
    XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value1')"));

    auto query_result_1 = db->execute_query("select * from test_table");
    XCTAssertTrue(query_result_1);
    XCTAssertTrue(query_result_1.value()->next());
    XCTAssertFalse(query_result_1.value()->next());

    XCTAssertTrue(db::begin_transaction(db));
    XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value2')"));
    XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value3')"));
    XCTAssertTrue(db::commit(db));

    auto query_result_2 = db->execute_query("select * from test_table");
    XCTAssertTrue(query_result_2);
    XCTAssertTrue(query_result_2.value()->next());
    XCTAssertTrue(query_result_2.value()->next());
    XCTAssertTrue(query_result_2.value()->next());
    XCTAssertFalse(query_result_2.value()->next());
}

- (void)test_transaction_rollback {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db->execute_update(db::create_table_sql("test_table", {"test_field"})));
    XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value1')"));

    auto query_result_1 = db->execute_query("select * from test_table");
    XCTAssertTrue(query_result_1);
    XCTAssertTrue(query_result_1.value()->next());
    XCTAssertFalse(query_result_1.value()->next());

    XCTAssertTrue(db::begin_transaction(db));
    XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value2')"));
    XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value3')"));
    XCTAssertTrue(db::rollback(db));

    auto query_result_2 = db->execute_query("select * from test_table");
    XCTAssertTrue(query_result_2);
    XCTAssertTrue(query_result_2.value()->next());
    XCTAssertFalse(query_result_2.value()->next());
}

- (void)test_save_point {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"test_field"}));

    auto count_of_row = [&db]() {
        auto query_result = db->execute_query("select * from test_table");
        int count = 0;
        while (query_result.value()->next()) {
            ++count;
        }
        return count;
    };

    XCTAssertEqual(count_of_row(), 0);
    XCTAssertTrue(db::start_save_point(db, "sp_1"));
    XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value1')"));
    XCTAssertEqual(count_of_row(), 1);
    XCTAssertTrue(db::start_save_point(db, "sp_2"));
    XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value2')"));
    XCTAssertEqual(count_of_row(), 2);
    XCTAssertTrue(db::rollback_save_point(db, "sp_2"));
    XCTAssertEqual(count_of_row(), 1);
    XCTAssertTrue(db::release_save_point(db, "sp_1"));
    XCTAssertEqual(count_of_row(), 1);
}

- (void)test_in_save_point {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db->execute_update(db::create_table_sql("test_table", {"test_field"})));

    auto count_of_row = [&db]() {
        auto query_result = db->execute_query("select * from test_table");
        int count = 0;
        while (query_result.value()->next()) {
            ++count;
        }
        return count;
    };

    XCTAssertTrue(db::in_save_point(db, [&db, &count_of_row, &self](bool &should_rollback) {
        XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value1')"));
        XCTAssertEqual(count_of_row(), 1);
    }));

    XCTAssertEqual(count_of_row(), 1);
}

- (void)test_in_save_point_rollback {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"test_field"}));

    auto count_of_row = [&db]() {
        auto query_result = db->execute_query("select * from test_table");
        int count = 0;
        while (query_result.value()->next()) {
            ++count;
        }
        return count;
    };

    XCTAssertTrue(db::in_save_point(db, [&db, &count_of_row, &self](bool &should_rollback) {
        XCTAssertTrue(db->execute_update("insert into test_table(test_field) values('value1')"));
        XCTAssertEqual(count_of_row(), 1);
        should_rollback = true;
    }));

    XCTAssertEqual(count_of_row(), 0);
}

- (void)test_savepoint_failed {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertFalse(db::start_save_point(db, ""));
    XCTAssertFalse(db::release_save_point(db, ""));
    XCTAssertFalse(db::rollback_save_point(db, ""));
}

- (void)test_table_exists {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"field"}));

    XCTAssertTrue(db::table_exists(db, "test_table"));
    XCTAssertFalse(db::table_exists(db, "hoge"));
}

- (void)test_index_exists {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"field"}));

    XCTAssertFalse(db::index_exists(db, "test_index"));

    XCTAssertTrue(db::create_index(db, "test_index", "test_table", {"field"}));

    XCTAssertTrue(db::index_exists(db, "test_index"));
    XCTAssertFalse(db::index_exists(db, "hoge"));

    XCTAssertTrue(db::drop_index(db, "test_index"));

    XCTAssertFalse(db::index_exists(db, "test_index"));
}

- (void)test_column_exists {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"field_a", "field_b"}));

    XCTAssertTrue(db::column_exists(db, "field_a", "test_table"));
    XCTAssertTrue(db::column_exists(db, "field_b", "test_table"));

    XCTAssertFalse(db::column_exists(db, "field_a", "hoge"));
    XCTAssertFalse(db::column_exists(db, "hoge", "test_table"));
}

- (void)test_get_schema {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    std::string const sql = "create table test_table (test_field)";
    XCTAssertTrue(db->execute_update(sql));

    auto row_set = db::get_schema(db);
    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set->next());

    auto map = row_set->values();

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
    XCTAssertEqual(rootpage_column_value.get<db::integer>(), 2);

    XCTAssertGreaterThan(map.count("type"), 0);
    auto &type_column_value = map.at("type");
    XCTAssertTrue(type_column_value.type() == typeid(db::text));
    XCTAssertEqual(type_column_value.get<db::text>(), "table");

    XCTAssertFalse(row_set->next());
}

- (void)test_get_table_schema {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"field_a", "field_b"}));

    auto row_set = db::get_table_schema(db, "test_table");
    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set->next());

    auto map = row_set->values();

    XCTAssertGreaterThan(map.count("pk"), 0);
    XCTAssertGreaterThan(map.count("dflt_value"), 0);
    XCTAssertGreaterThan(map.count("type"), 0);
    XCTAssertGreaterThan(map.count("notnull"), 0);
    XCTAssertGreaterThan(map.count("name"), 0);
    XCTAssertGreaterThan(map.count("cid"), 0);

    XCTAssertEqual(map.at("name").get<db::text>(), "field_a");

    XCTAssertTrue(row_set->next());

    map = row_set->values();

    XCTAssertEqual(map.at("name").get<db::text>(), "field_b");

    XCTAssertFalse(row_set->next());
}

- (void)test_get_index_schema {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    XCTAssertTrue(db::create_table(db, "test_table", {"field_a", "field_b"}));
    XCTAssertTrue(db::create_index(db, "test_index", "test_table", {"field_a"}));

    auto row_set = db::get_index_schema(db, "test_index");
    XCTAssertTrue(row_set);
    XCTAssertTrue(row_set->next());

    auto map = row_set->values();

    XCTAssertEqual(map.at("type"), db::value{"index"});
    XCTAssertEqual(map.at("name"), db::value{"test_index"});
    XCTAssertEqual(map.at("tbl_name"), db::value{"test_table"});
}

- (void)test_select {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    auto const table = "table_a";
    auto const field_a = "field_a";
    auto const field_b = "field_b";

    XCTAssertTrue(db::create_table(db, table, {field_a, field_b}));

    db::value_vector_t args_1{db::value{"value_a_1"}, db::value{"value_b_1"}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table, {field_a, field_b}), std::move(args_1)));

    db::value_vector_t args_2{db::value{"value_a_2"}, db::value{"value_b_2"}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table, {field_a, field_b}), std::move(args_2)));

    auto const select_result = db::select(db, {.table = table,
                                               .fields = {field_a, field_b},
                                               .arguments = {std::make_pair(field_a, db::value{"value_a_2"})},
                                               .where_exprs = db::field_expr(field_a, "=")});

    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 1);
}

- (void)test_max {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> fields = {field_name};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    XCTAssertFalse(db::max(db, table_name, field_name));

    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), {db::value{1}}));

    XCTAssertEqual(db::max(db, table_name, field_name), db::value{1});

    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), {db::value{10}}));

    XCTAssertEqual(db::max(db, table_name, field_name), db::value{10});

    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), {db::value{5}}));

    XCTAssertEqual(db::max(db, table_name, field_name), db::value{10});
}

- (void)test_select_in_object_ids {
    db::database_ptr const db = [yas_db_test_utils create_test_database];
    XCTAssertTrue(db->open());

    auto const table_name = "table_a";
    auto const field_name = "field_a";
    std::vector<std::string> const fields{db::object_id_field, field_name};

    XCTAssertTrue(db::create_table(db, table_name, fields));

    db::value_vector_t args;
    args = {db::value{1}, db::value{"value_1"}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{2}, db::value{"value_2"}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{3}, db::value{"value_3"}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{4}, db::value{"value_4"}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{5}, db::value{"value_5"}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));
    args = {db::value{6}, db::value{"value_6"}};
    XCTAssertTrue(db->execute_update(db::insert_sql(table_name, fields), args));

    db::select_option option;
    option.table = table_name;
    option.where_exprs = db::in_expr(db::object_id_field, db::integer_set_t{2, 4, 6});
    option.field_orders = {db::field_order{db::object_id_field, db::order::ascending}};

    auto select_result = db::select(db, option);

    XCTAssertTrue(select_result);
    XCTAssertEqual(select_result.value().size(), 3);
    XCTAssertEqual(select_result.value().at(0).at(field_name), db::value{"value_2"});
    XCTAssertEqual(select_result.value().at(1).at(field_name), db::value{"value_4"});
    XCTAssertEqual(select_result.value().at(2).at(field_name), db::value{"value_6"});
}

- (void)test_to_object_map {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj_a0 = db::object::make_shared(model.entity("sample_a"));
    auto obj_a1 = db::object::make_shared(model.entity("sample_a"));

    db::manageable_object::cast(obj_a0)->load_data({.object_id = db::make_stable_id(db::value{0})});
    db::manageable_object::cast(obj_a1)->load_data({.object_id = db::make_stable_id(db::value{1})});

    obj_a0->set_attribute_value("name", db::value{"a0"});
    obj_a1->set_attribute_value("name", db::value{"a1"});

    db::object_vector_t src_vec;
    src_vec.emplace_back(std::move(obj_a0));
    src_vec.emplace_back(std::move(obj_a1));

    XCTAssertEqual(src_vec.size(), 2);
    XCTAssertTrue(src_vec.at(0));
    XCTAssertTrue(src_vec.at(1));

    auto dst_map = to_object_map(std::move(src_vec));

    XCTAssertEqual(dst_map.size(), 2);
    XCTAssertEqual(dst_map.count(0), 1);
    XCTAssertEqual(dst_map.count(1), 1);
    XCTAssertEqual(dst_map.at(0)->attribute_value("name"), db::value{"a0"});
    XCTAssertEqual(dst_map.at(1)->attribute_value("name"), db::value{"a1"});

    XCTAssertEqual(src_vec.size(), 0);
}

- (void)test_to_object_map_map {
    db::model model = [yas_db_test_utils model_0_0_1];

    auto obj_a0 = db::object::make_shared(model.entity("sample_a"));
    auto obj_a1 = db::object::make_shared(model.entity("sample_a"));
    auto obj_b0 = db::object::make_shared(model.entity("sample_b"));
    auto obj_b1 = db::object::make_shared(model.entity("sample_b"));

    db::manageable_object::cast(obj_a0)->load_data({.object_id = db::make_stable_id(db::value{0})});
    db::manageable_object::cast(obj_a1)->load_data({.object_id = db::make_stable_id(db::value{1})});
    db::manageable_object::cast(obj_b0)->load_data({.object_id = db::make_stable_id(db::value{2})});
    db::manageable_object::cast(obj_b1)->load_data({.object_id = db::make_stable_id(db::value{3})});

    obj_a0->set_attribute_value("name", db::value{"a0"});
    obj_a1->set_attribute_value("name", db::value{"a1"});
    obj_b0->set_attribute_value("name", db::value{"b2"});
    obj_b1->set_attribute_value("name", db::value{"b3"});

    db::object_vector_map_t src_map;
    db::object_vector_t object_as;
    object_as.emplace_back(std::move(obj_a0));
    object_as.emplace_back(std::move(obj_a1));
    src_map.emplace("sample_a", std::move(object_as));
    db::object_vector_t object_bs;
    object_bs.emplace_back(std::move(obj_b0));
    object_bs.emplace_back(std::move(obj_b1));
    src_map.emplace("sample_b", std::move(object_bs));

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
    XCTAssertEqual(dst_map.at("sample_a").at(0)->attribute_value("name"), db::value{"a0"});
    XCTAssertEqual(dst_map.at("sample_a").at(1)->attribute_value("name"), db::value{"a1"});
    XCTAssertEqual(dst_map.at("sample_b").at(2)->attribute_value("name"), db::value{"b2"});
    XCTAssertEqual(dst_map.at("sample_b").at(3)->attribute_value("name"), db::value{"b3"});

    XCTAssertEqual(src_map.size(), 0);
    XCTAssertEqual(src_map.count("sample_a"), 0);
    XCTAssertEqual(src_map.count("sample_b"), 0);
}

@end
