//
//  yas_db_sql_utils.cpp
//

#include <sstream>
#include "yas_db_order.h"
#include "yas_db_sql_utils.h"
#include "yas_stl_utils.h"

using namespace yas;

namespace yas {
namespace db {
    static std::string const field_separator = ", ";
}
}

std::string yas::db::create_table_sql(std::string const &table, std::vector<std::string> const &fields) {
    std::string const joined_fields = joined(fields, field_separator);
    return "create table if not exists " + table + " (" + joined_fields + ");";
}

std::string yas::db::alter_table_sql(std::string const &table, std::string const &field) {
    return "alter table " + table + " add column " + field + ";";
}

std::string yas::db::drop_table_sql(std::string const &table) {
    return "drop table if exists " + table + ";";
}

std::string yas::db::insert_sql(const std::string &table, const std::vector<std::string> &fields) {
    std::ostringstream stream;
    stream << "insert into " + table;
    if (fields.size() > 0) {
        std::string const joined_fields = joined(fields, field_separator);
        std::string const joined_values =
            joined(map<std::string>(fields, [](std::string const &field) { return ":" + field; }), field_separator);
        stream << "(" + joined_fields + ") values(" + joined_values + ");";
    } else {
        stream << " default values;";
    }
    return stream.str();
}

std::string yas::db::update_sql(const std::string &table, const std::vector<std::string> &fields,
                                const std::string &where_exprs) {
    std::ostringstream stream;
    stream << "update " << table << " set "
           << joined(map<std::string>(fields, [](std::string const &field) { return equal_field(field); }),
                     field_separator);
    if (where_exprs.size() > 0) {
        stream << " where " << where_exprs;
    }
    stream << ";";
    return stream.str();
}

std::string yas::db::delete_sql(const std::string &table, const std::string &where_exprs) {
    std::ostringstream stream;
    stream << "delete from " << table;
    if (where_exprs.size() > 0) {
        stream << " where " << where_exprs;
    }
    stream << ";";
    return stream.str();
}

std::string yas::db::expr(std::string const &left, std::string const &right, std::string const &op) {
    return "(" + left + " " + op + " " + right + ")";
}

std::string yas::db::field_expr(std::string const &field, std::string const &op) {
    return expr(field, ":" + field, op);
}

std::string yas::db::equal_field(std::string const &field) {
    return field + " = :" + field;
}

std::string yas::db::joined_orders(std::vector<field_order> const &orders) {
    auto mapped = map<std::string>(orders, [](auto const &order) { return order.sql(); });
    return joined(mapped, field_separator);
}

std::string yas::db::select_sql(std::string const &table_name, std::vector<std::string> const &fields,
                                std::string const &where_exprs, std::vector<field_order> const &orders,
                                range const &limit_range) {
    std::ostringstream stream;

    std::string const joined_fields = joined(fields, field_separator);

    stream << "select " << joined_fields << " from " << table_name;

    if (where_exprs.size() > 0) {
        stream << " where " << where_exprs;
    }

    if (orders.size() > 0) {
        stream << " order by " << joined_orders(orders);
    }

    if (!limit_range.is_empty()) {
        stream << " limit " << limit_range.sql();
    }

    stream << ";";
    return stream.str();
}

std::string yas::db::foreign_key(std::string const &field, std::string const &ref_table, std::string const &ref_field,
                                 std::string const &on_update, std::string const &on_delete) {
    std::ostringstream stream;
    stream << "foreign key (" + field + ") references " + ref_table + "(" + ref_field + ")";
    if (on_update.size() > 0) {
        stream << " on update " << on_update;
    }
    if (on_delete.size() > 0) {
        stream << " on delete " << on_delete;
    }
    return stream.str();
}
