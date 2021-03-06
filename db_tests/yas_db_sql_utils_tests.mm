//
//  yas_db_sql_utils.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_sql_utils : XCTestCase

@end

@implementation yas_db_sql_utils

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create_table_sql {
    XCTAssertEqual(db::create_table_sql("test_table", {"field_a", "field_b"}),
                   "CREATE TABLE IF NOT EXISTS test_table (field_a, field_b);");
}

- (void)test_alter_table_sql {
    XCTAssertEqual(db::alter_table_sql("test_table", "field_a"), "ALTER TABLE test_table ADD COLUMN field_a;");
}

- (void)test_drop_table_sql {
    XCTAssertEqual(db::drop_table_sql("test_table"), "DROP TABLE IF EXISTS test_table;");
}

- (void)test_create_index_sql {
    XCTAssertEqual(db::create_index_sql("idx_name", "table_name", {"attr_a", "attr_b"}),
                   "CREATE INDEX IF NOT EXISTS idx_name ON table_name(attr_a,attr_b);");
}

- (void)test_drop_index_sql {
    XCTAssertEqual(db::drop_index_sql("idx_name"), "DROP INDEX IF EXISTS idx_name;");
}

- (void)test_insert_sql {
    XCTAssertEqual(db::insert_sql("aaa", {"abc", "def"}), "INSERT INTO aaa(abc, def) VALUES(:abc, :def);");
    XCTAssertEqual(db::insert_sql("bbb"), "INSERT INTO bbb DEFAULT VALUES;");
}

- (void)test_update_sql {
    XCTAssertEqual(db::update_sql("ccc", {"qwe", "rty"}, "(uio = :uio)"),
                   "UPDATE ccc SET qwe = :qwe, rty = :rty WHERE (uio = :uio);");
}

- (void)test_delete_sql {
    XCTAssertEqual(db::delete_sql("bbb", "xyz = :xyz"), "DELETE FROM bbb WHERE xyz = :xyz;");
}

- (void)test_expr {
    XCTAssertEqual(db::expr("abc", "=", ":def"), "(abc = :def)");
}

- (void)test_field_expr {
    XCTAssertEqual(db::field_expr("abc", "="), "(abc = :abc)");
}

- (void)test_equal_field_expr {
    XCTAssertEqual(db::equal_field_expr("abc"), "(abc = :abc)");
}

- (void)test_joined_orders {
    auto joined_orders = db::joined_orders({{"field_a", db::order::ascending}, {"field_b", db::order::descending}});
    XCTAssertEqual(joined_orders, "field_a ASC, field_b DESC");
}

- (void)test_select_sql_with_params {
    auto select_sql =
        db::select_sql("test_table", {"field_a", "field_b"}, "abc = :def",
                       {{"field_c", db::order::ascending}, {"field_d", db::order::descending}}, {10, 20}, "ghi", false);
    XCTAssertEqual(select_sql,
                   "SELECT field_a, field_b FROM test_table WHERE abc = :def ORDER BY field_c ASC, field_d DESC LIMIT "
                   "10, 20 GROUP BY ghi");
}

- (void)test_select_sql_by_select_option {
    auto const option =
        db::select_option{.table = "test_table",
                          .fields = {"field_a", "field_b"},
                          .where_exprs = "abc = :def",
                          .field_orders = {{"field_c", db::order::ascending}, {"field_d", db::order::descending}},
                          .limit_range = {10, 20},
                          .group_by = "ghi",
                          .distinct = true};
    auto select_sql = db::select_sql(option);
    XCTAssertEqual(select_sql,
                   "SELECT DISTINCT field_a, field_b FROM test_table WHERE abc = :def ORDER BY field_c ASC, field_d "
                   "DESC LIMIT 10, 20 GROUP BY ghi");
}

- (void)test_in_expr_with_text_values {
    auto in_expr = db::in_expr("test_field", db::value_vector_t{db::value{"value_a"}, db::value{"value_b"}});
    XCTAssertEqual(in_expr, "test_field IN ('value_a', 'value_b')");
}

- (void)test_in_expr_with_integer_values {
    auto in_expr = db::in_expr("test_field", db::value_vector_t{db::value{1}, db::value{2}});
    XCTAssertEqual(in_expr, "test_field IN (1, 2)");
}

- (void)test_in_expr_with_select_option {
    auto in_expr = db::in_expr("test_field", {.table = "test_table", .fields = {"field_a"}});
    XCTAssertEqual(in_expr, "test_field IN (SELECT field_a FROM test_table)");
}

- (void)test_in_expr_with_integer_set {
    auto in_expr = db::in_expr("test_field", db::integer_set_t{1, 2});
    XCTAssertEqual(in_expr, "test_field IN (1, 2)");
}

@end
