//
//  yas_sql_utils.cpp
//

#include <sstream>
#include "yas_db_sql_utils.h"
#include "yas_stl_utils.h"

using namespace yas;

namespace yas {
namespace db {
    static std::string const field_separator = ", ";
}
}

std::string yas::db::insert_sql(const std::string &table, const std::vector<std::string> &fields) {
    std::string const joined_fields = joined(fields, field_separator);
    std::string const joined_values =
        joined(map(fields, [](std::string const &field) { return ":" + field; }), field_separator);
    return "insert into " + table + "(" + joined_fields + ") values(" + joined_values + ");";
}

std::string yas::db::update_sql(const std::string &table, const std::vector<std::string> &fields,
                                const std::string &where) {
    std::ostringstream stream;
    stream << "update " << table << " set "
           << joined(map(fields, [](std::string const &field) { return equal_expr(field); }), field_separator);
    if (where.size() > 0) {
        stream << " where " << where;
    }
    stream << ";";
    return stream.str();
}

std::string yas::db::delete_sql(const std::string &table, const std::string &where) {
    std::ostringstream stream;
    stream << "delete from " << table;
    if (where.size() > 0) {
        stream << " where " << where;
    }
    stream << ";";
    return stream.str();
}

std::string yas::db::expr(std::string const &field, std::string const &op) {
    return field + " " + op + " :" + field;
}

std::string yas::db::equal_expr(std::string const &field) {
    return expr(field, "=");
}

std::string yas::db::joined_exprs(const std::vector<std::string> &fields) {
    return joined(map(fields, [](std::string const &field) { return equal_expr(field); }), " and ");
}

std::string yas::db::joined_orders(std::vector<field_order> const &orders) {
    auto mapped = map<field_order, std::string>(orders, [](auto const &order) { return order.sql(); });
    return joined(mapped, field_separator);
}
