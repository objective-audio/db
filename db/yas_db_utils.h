//
//  yas_db_utils.h
//

#pragma once

namespace yas {
namespace db {
    class database;

    update_result create_table(database &db, std::string const &table_name, std::vector<std::string> const &fields);
    update_result alter_table(database &db, std::string const &table_name, std::string const &field);
    update_result drop_table(database &db, std::string const &table_name);

    update_result begin_transaction(database &db);
    update_result begin_deferred_transaction(database &db);
    update_result commit(database &db);
    update_result rollback(database &db);

#if SQLITE_VERSION_NUMBER >= 3007000
    update_result start_save_point(database &db, std::string const &name);
    update_result release_save_point(database &db, std::string const &name);
    update_result rollback_save_point(database &db, std::string const &name);

    update_result in_save_point(database &db, std::function<void(bool &rollback)> const function);
#endif

    bool table_exists(database const &db, std::string const &table_name);
    db::row_set get_schema(database const &db);
    db::row_set get_table_schema(database const &db, std::string const &table_name);
    bool column_exists(database const &db, std::string const &column_name, std::string const &table_name);

    std::vector<db::column_map> select(database const &db, std::string const &table_name,
                                       std::vector<std::string> const &fields, std::string const &where_exprs = "",
                                       std::vector<db::column_map> const &parameter_maps = {},
                                       std::vector<db::field_order> const &orders = {},
                                       db::range const &limit_range = db::range::empty());
}
}