//
//  yas_db_sql_utils.cpp
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

std::string yas::db::create_table_sql(std::string const &table, std::vector<std::string> const &fields) {
    std::string const joined_fields = joined(fields, field_separator);
    return "CREATE TABLE IF NOT EXISTS " + table + " (" + joined_fields + ");";
}

std::string yas::db::alter_table_sql(std::string const &table, std::string const &field) {
    return "ALTER TABLE " + table + " ADD COLUMN " + field + ";";
}

std::string yas::db::drop_table_sql(std::string const &table) {
    return "DROP TABLE IF EXISTS " + table + ";";
}

std::string db::create_index_sql(std::string const &index, std::string const &table,
                                 std::vector<std::string> const &fields) {
    return "CREATE INDEX IF NOT EXISTS " + index + " ON " + table + "(" + joined(fields, ",") + ");";
}

std::string db::drop_index_sql(std::string const &index) {
    return "DROP INDEX IF EXISTS " + index + ";";
}

std::string yas::db::insert_sql(std::string const &table, std::vector<std::string> const &fields) {
    std::ostringstream stream;
    stream << "INSERT INTO " + table;
    if (fields.size() > 0) {
        std::string const joined_fields = joined(fields, field_separator);
        std::string const joined_values = joined(
            to_vector<std::string>(fields, [](std::string const &field) { return ":" + field; }), field_separator);
        stream << "(" + joined_fields + ") VALUES(" + joined_values + ");";
    } else {
        stream << " DEFAULT VALUES;";
    }
    return stream.str();
}

std::string yas::db::update_sql(std::string const &table, std::vector<std::string> const &fields,
                                std::string const &where_exprs) {
    std::ostringstream stream;
    stream << "UPDATE " << table << " SET "
           << joined(to_vector<std::string>(fields, [](std::string const &field) { return equal_field(field); }),
                     field_separator);
    if (where_exprs.size() > 0) {
        stream << " WHERE " << where_exprs;
    }
    stream << ";";
    return stream.str();
}

std::string yas::db::delete_sql(const std::string &table, const std::string &where_exprs) {
    std::ostringstream stream;
    stream << "DELETE FROM " << table;
    if (where_exprs.size() > 0) {
        stream << " WHERE " << where_exprs;
    }
    stream << ";";
    return stream.str();
}

std::string yas::db::expr(std::string const &left, std::string const &op, std::string const &right) {
    return "(" + left + " " + op + " " + right + ")";
}

std::string yas::db::field_expr(std::string const &field, std::string const &op) {
    return expr(field, op, ":" + field);
}

std::string yas::db::equal_field_expr(std::string const &field) {
    return field_expr(field, "=");
}

std::string yas::db::equal_field(std::string const &field) {
    return field + " = :" + field;
}

std::string yas::db::joined_orders(std::vector<field_order> const &orders) {
    auto mapped = to_vector<std::string>(orders, [](auto const &order) { return order.sql(); });
    return joined(mapped, field_separator);
}

std::string yas::db::select_sql(std::string const &table_name, std::vector<std::string> const &fields,
                                std::string const &where_exprs, std::vector<field_order> const &orders,
                                range const &limit_range) {
    if (table_name.size() == 0) {
        throw "table_name size is zero.";
    }

    std::ostringstream stream;

    std::string const joined_fields = joined(fields, field_separator);

    stream << "SELECT " << joined_fields << " FROM " << table_name;

    if (where_exprs.size() > 0) {
        stream << " WHERE " << where_exprs;
    }

    if (orders.size() > 0) {
        stream << " ORDER BY " << joined_orders(orders);
    }

    if (!limit_range.is_empty()) {
        stream << " LIMIT " << limit_range.sql();
    }

    stream << ";";
    return stream.str();
}

std::string yas::db::foreign_key(std::string const &field, std::string const &ref_table, std::string const &ref_field,
                                 std::string const &on_update, std::string const &on_delete) {
    std::ostringstream stream;
    stream << "FOREIGN KEY (" + field + ") REFERENCES " + ref_table + "(" + ref_field + ")";
    if (on_update.size() > 0) {
        stream << " ON UPDATE " << on_update;
    }
    if (on_delete.size() > 0) {
        stream << " ON DELETE " << on_delete;
    }
    return stream.str();
}

std::string yas::db::vacuum_sql() {
    return "VACUUM;";
}
