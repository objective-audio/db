//
//  yas_db_sql_utils.h
//

#pragma once

#include <vector>
#include "yas_db_select_option.h"
#include "yas_db_additional_types.h"

namespace yas {
namespace db {
    class field_order;
    class range;

    std::string create_table_sql(std::string const &table, std::vector<std::string> const &fields);
    std::string alter_table_sql(std::string const &table, std::string const &field);
    std::string drop_table_sql(std::string const &table);

    std::string create_index_sql(std::string const &index, std::string const &table,
                                 std::vector<std::string> const &fields);
    std::string drop_index_sql(std::string const &index);

    std::string insert_sql(std::string const &table, std::vector<std::string> const &fields = {});
    std::string update_sql(std::string const &table, std::vector<std::string> const &fields,
                           std::string const &where_exprs = "");
    std::string delete_sql(std::string const &table, std::string const &where_exprs = "");

    std::string expr(std::string const &left, std::string const &op, std::string const &right);
    std::string field_expr(std::string const &field, std::string const &op);
    std::string equal_field_expr(std::string const &field);
    std::string in_expr(std::string const &field, std::string const &select_sql);
    std::string in_expr(std::string const &field, db::value_vector_t const &values);
    std::string in_expr(std::string const &field, db::integer_set_t const &ids);

    std::string equal_field(std::string const &field);

    std::string joined_orders(std::vector<db::field_order> const &orders);

    std::string select_sql(std::string const &table_name, std::vector<std::string> const &fields,
                           std::string const &where_exprs = std::string(),
                           std::vector<db::field_order> const &orders = {},
                           db::range const &limit_range = db::empty_range(), bool const distinct = false);
    std::string select_sql(db::select_option const &option);

    std::string foreign_key(std::string const &field, std::string const &ref_table, std::string const &ref_field,
                            std::string const &on_update, std::string const &on_delete);

    std::string vacuum_sql();
}
}
