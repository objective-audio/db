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
                   "create table if not exists test_table (field_a, field_b);");
}

- (void)test_alter_table_sql {
    XCTAssertEqual(db::alter_table_sql("test_table", "field_a"), "alter table test_table add column field_a;");
}

- (void)test_drop_table_sql {
    XCTAssertEqual(db::drop_table_sql("test_table"), "drop table if exists test_table;");
}

- (void)test_insert_sql {
    XCTAssertEqual(db::insert_sql("aaa", {"abc", "def"}), "insert into aaa(abc, def) values(:abc, :def);");
    XCTAssertEqual(db::insert_sql("bbb"), "insert into bbb default values;");
}

- (void)test_update_sql {
    XCTAssertEqual(db::update_sql("ccc", {"qwe", "rty"}, "(uio = :uio)"),
                   "update ccc set qwe = :qwe, rty = :rty where (uio = :uio);");
}

- (void)test_delete_sql {
    XCTAssertEqual(db::delete_sql("bbb", "xyz = :xyz"), "delete from bbb where xyz = :xyz;");
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
    XCTAssertEqual(joined_orders, "field_a asc, field_b desc");
}

- (void)test_select_sql {
    auto select_sql = db::select_sql("test_table", {"field_a", "field_b"}, "abc = :def",
                                     {{"field_c", db::order::ascending}, {"field_d", db::order::descending}}, {10, 20});
    XCTAssertEqual(
        select_sql,
        "select field_a, field_b from test_table where abc = :def order by field_c asc, field_d desc limit 10, 20;");
}

@end
