//
//  yas_db_sql_utils.h
//

#pragma once

#include <vector>
#include "yas_db_select_option.h"
#include "yas_db_value.h"

namespace yas {
namespace db {
    class field_order;
    class range;

    std::string create_table_sql(std::string const &table, std::vector<std::string> const &fields);
    std::string alter_table_sql(std::string const &table, std::string const &field);
    std::string drop_table_sql(std::string const &table);

    std::string insert_sql(std::string const &table, std::vector<std::string> const &fields = {});
    std::string update_sql(std::string const &table, std::vector<std::string> const &fields,
                           std::string const &where_exprs);
    std::string delete_sql(std::string const &table, std::string const &where_exprs);

    std::string expr(std::string const &left, std::string const &right, std::string const &op);
    std::string field_expr(std::string const &field, std::string const &op);

    std::string equal_field(std::string const &field);

    std::string joined_orders(std::vector<field_order> const &orders);

    std::string select_sql(std::string const &table_name, std::vector<std::string> const &fields,
                           std::string const &where_exprs = std::string(), std::vector<field_order> const &orders = {},
                           range const &limit_range = range::empty());

    std::string foreign_key(std::string const &field, std::string const &ref_table, std::string const &ref_field,
                            std::string const &on_update, std::string const &on_delete);
}
}