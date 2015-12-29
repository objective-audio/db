//
//  yas_sql_utils.h
//

#pragma once

#include <vector>
#include "yas_db_order.h"

namespace yas {
namespace db {
    std::string insert_sql(std::string const &table, std::vector<std::string> const &fields);
    std::string update_sql(std::string const &table, std::vector<std::string> const &fields,
                           std::string const &where);
    std::string delete_sql(std::string const &table, std::string const &where);

    std::string expr(std::string const &field, std::string const &op);
    std::string equal_expr(std::string const &field);
    std::string joined_exprs(std::vector<std::string> const &fields);

    std::string joined_orders(std::vector<field_order> const &orders);
}
}