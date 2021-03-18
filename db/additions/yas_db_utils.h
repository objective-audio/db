//
//  yas_db_utils.h
//

#pragma once

#include <db/yas_db_ptr.h>
#include <db/yas_db_types.h>

namespace yas::db {
class database;
class select_option;

using select_result_t = result<db::value_map_vector_t, db::error>;
using select_single_result_t = result<db::value_map_t, std::nullptr_t>;

db::update_result_t create_table(db::database_ptr const &db, std::string const &table_name,
                                 std::vector<std::string> const &fields);
db::update_result_t alter_table(db::database_ptr const &db, std::string const &table_name, std::string const &field);
db::update_result_t drop_table(db::database_ptr const &db, std::string const &table_name);

db::update_result_t create_index(db::database_ptr const &db, std::string const &index_name,
                                 std::string const &table_name, std::vector<std::string> const &fields);
db::update_result_t drop_index(db::database_ptr const &db, std::string const &index_name);

db::update_result_t begin_transaction(db::database_ptr const &db);
db::update_result_t begin_deferred_transaction(db::database_ptr const &db);
db::update_result_t commit(db::database_ptr const &db);
db::update_result_t rollback(db::database_ptr const &db);

#if SQLITE_VERSION_NUMBER >= 3007000
db::update_result_t start_save_point(db::database_ptr const &db, std::string const &name);
db::update_result_t release_save_point(db::database_ptr const &db, std::string const &name);
db::update_result_t rollback_save_point(db::database_ptr const &db, std::string const &name);

db::update_result_t in_save_point(db::database_ptr const &db, std::function<void(bool &rollback)> const function);
#endif

bool table_exists(db::database_ptr const &db, std::string const &table_name);
bool index_exists(db::database_ptr const &db, std::string const &index_name);
db::row_set_ptr get_schema(db::database_ptr const &db);
db::row_set_ptr get_table_schema(db::database_ptr const &db, std::string const &table_name);
db::row_set_ptr get_index_schema(db::database_ptr const &db, std::string const &index_name);
bool column_exists(db::database_ptr const &db, std::string column_name, std::string table_name);

db::select_result_t select(db::database_ptr const &db, db::select_option const &option);

db::select_single_result_t select_single(db::database_ptr const &db, db::select_option option);

db::value max(db::database_ptr const &db, std::string const &table_name, std::string const &field);
}  // namespace yas::db
