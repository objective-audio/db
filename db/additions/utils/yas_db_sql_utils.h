//
//  yas_db_sql_utils.h
//

#pragma once

#include <db/yas_db_additional_types.h>
#include <db/yas_db_select_option.h>

#include <vector>

namespace yas::db {
class field_order;
class range;

[[nodiscard]] std::string create_table_sql(std::string const &table, std::vector<std::string> const &fields);
[[nodiscard]] std::string alter_table_sql(std::string const &table, std::string const &field);
[[nodiscard]] std::string drop_table_sql(std::string const &table);

[[nodiscard]] std::string create_index_sql(std::string const &index, std::string const &table,
                                           std::vector<std::string> const &fields);
[[nodiscard]] std::string drop_index_sql(std::string const &index);

[[nodiscard]] std::string insert_sql(std::string const &table, std::vector<std::string> const &fields = {});
[[nodiscard]] std::string update_sql(std::string const &table, std::vector<std::string> const &fields,
                                     std::string const &where_exprs = "");
[[nodiscard]] std::string delete_sql(std::string const &table, std::string const &where_exprs = "");

[[nodiscard]] std::string expr(std::string const &left, std::string const &op, std::string const &right);
[[nodiscard]] std::string field_expr(std::string const &field, std::string const &op);
[[nodiscard]] std::string equal_field_expr(std::string const &field);
[[nodiscard]] std::string in_expr(std::string const &field, db::select_option const &select_option);
[[nodiscard]] std::string in_expr(std::string const &field, db::value_vector_t const &values);
[[nodiscard]] std::string in_expr(std::string const &field, db::integer_set_t const &ids);

[[nodiscard]] std::string equal_field(std::string const &field);

[[nodiscard]] std::string joined_orders(std::vector<db::field_order> const &orders);

[[nodiscard]] std::string select_sql(std::string const &table_name, std::vector<std::string> const &fields,
                                     std::string const &where_exprs, std::vector<db::field_order> const &orders,
                                     db::range const &limit_range, std::string const &group_by, bool const distinct);
[[nodiscard]] std::string select_sql(db::select_option const &option);

[[nodiscard]] std::string foreign_key(std::string const &field, std::string const &ref_table,
                                      std::string const &ref_field, std::string const &on_update,
                                      std::string const &on_delete);

[[nodiscard]] std::string vacuum_sql();
}  // namespace yas::db
