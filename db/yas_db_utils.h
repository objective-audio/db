//
//  yas_db_utils.h
//

#pragma once

namespace yas {
namespace db {
    class database;
    class select_option;

    using select_result_t = result<value_map_vector_t, error>;
    using select_single_result_t = result<value_map_t, std::nullptr_t>;

    update_result_t create_table(database &db, std::string const &table_name, std::vector<std::string> const &fields);
    update_result_t alter_table(database &db, std::string const &table_name, std::string const &field);
    update_result_t drop_table(database &db, std::string const &table_name);

    update_result_t create_index(database &db, std::string const &index_name, std::string const &table_name,
                               std::vector<std::string> const &fields);
    update_result_t drop_index(database &db, std::string const &index_name);

    update_result_t begin_transaction(database &db);
    update_result_t begin_deferred_transaction(database &db);
    update_result_t commit(database &db);
    update_result_t rollback(database &db);

#if SQLITE_VERSION_NUMBER >= 3007000
    update_result_t start_save_point(database &db, std::string const &name);
    update_result_t release_save_point(database &db, std::string const &name);
    update_result_t rollback_save_point(database &db, std::string const &name);

    update_result_t in_save_point(database &db, std::function<void(bool &rollback)> const function);
#endif

    bool table_exists(database const &db, std::string const &table_name);
    bool index_exists(database const &db, std::string const &index_name);
    row_set get_schema(database const &db);
    row_set get_table_schema(database const &db, std::string const &table_name);
    row_set get_index_schema(database const &db, std::string const &index_name);
    bool column_exists(database const &db, std::string column_name, std::string table_name);

    select_result_t select(database const &db, select_option const &option);
    select_result_t select_last(database const &db, select_option option, value const &save_id = nullptr,
                              bool const include_removed = false);
    select_result_t select_undo(database const &db, std::string const &table_name, integer::type const revert_save_id,
                              integer::type const current_save_id);
    select_result_t select_redo(database const &db, std::string const &table_name, integer::type const revert_save_id,
                              integer::type const current_save_id);
    select_result_t select_revert(database const &db, std::string const &table_name, integer::type const revert_save_id,
                                integer::type const current_save_id);

    select_single_result_t select_single(database const &db, select_option option);
    select_single_result_t select_db_info(database const &db);

    update_result_t purge(database &db, std::string const &table_name);
    update_result_t purge_relation(database &db, std::string const &table_name, std::string const &src_table_name);

    value max(database const &db, std::string const &table_name, std::string const &field);
}
}
