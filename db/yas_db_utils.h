//
//  yas_db_utils.h
//

#pragma once

namespace yas {
namespace db {
    class database;
    class select_option;

    using select_result_t = result<db::value_map_vector_t, error>;
    using select_single_result_t = result<db::value_map_t, std::nullptr_t>;

    db::update_result_t create_table(db::database &db, std::string const &table_name,
                                     std::vector<std::string> const &fields);
    db::update_result_t alter_table(db::database &db, std::string const &table_name, std::string const &field);
    db::update_result_t drop_table(db::database &db, std::string const &table_name);

    db::update_result_t create_index(db::database &db, std::string const &index_name, std::string const &table_name,
                                     std::vector<std::string> const &fields);
    db::update_result_t drop_index(db::database &db, std::string const &index_name);

    db::update_result_t begin_transaction(db::database &db);
    db::update_result_t begin_deferred_transaction(db::database &db);
    db::update_result_t commit(db::database &db);
    db::update_result_t rollback(db::database &db);

#if SQLITE_VERSION_NUMBER >= 3007000
    db::update_result_t start_save_point(db::database &db, std::string const &name);
    db::update_result_t release_save_point(db::database &db, std::string const &name);
    db::update_result_t rollback_save_point(db::database &db, std::string const &name);

    db::update_result_t in_save_point(db::database &db, std::function<void(bool &rollback)> const function);
#endif

    bool table_exists(db::database const &db, std::string const &table_name);
    bool index_exists(db::database const &db, std::string const &index_name);
    db::row_set get_schema(db::database const &db);
    db::row_set get_table_schema(db::database const &db, std::string const &table_name);
    db::row_set get_index_schema(db::database const &db, std::string const &index_name);
    bool column_exists(db::database const &db, std::string column_name, std::string table_name);

    db::select_result_t select(db::database const &db, db::select_option const &option);
    db::select_result_t select_last(db::database const &db, db::select_option option, value const &save_id = nullptr,
                                    bool const include_removed = false);
    db::select_result_t select_undo(db::database const &db, std::string const &table_name,
                                    db::integer::type const revert_save_id, db::integer::type const current_save_id);
    db::select_result_t select_redo(db::database const &db, std::string const &table_name,
                                    db::integer::type const revert_save_id, db::integer::type const current_save_id);
    db::select_result_t select_revert(db::database const &db, std::string const &table_name,
                                      db::integer::type const revert_save_id, db::integer::type const current_save_id);

    db::select_single_result_t select_single(db::database const &db, db::select_option option);
    db::select_single_result_t select_db_info(db::database const &db);

    db::update_result_t purge(db::database &db, std::string const &table_name);
    db::update_result_t purge_relation(db::database &db, std::string const &table_name,
                                       std::string const &src_table_name);

    db::value max(db::database const &db, std::string const &table_name, std::string const &field);
}
}
