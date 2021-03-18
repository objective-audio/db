//
//  yas_db_database.cpp
//

#include "yas_db_database.h"

#include <cpp_utils/yas_fast_each.h>
#include <cpp_utils/yas_result.h>
#include <cpp_utils/yas_stl_utils.h>

#include <mutex>

#include "yas_db_error.h"
#include "yas_db_row_set.h"
#include "yas_db_statement.h"
#include "yas_db_value.h"

using namespace yas;
using namespace yas::db;

namespace yas::db {
static std::map<uint8_t, database_wptr> _databases;

static void bind(db::value const &value, int column_idx, sqlite3_stmt *stmt) {
    std::type_info const &type = value.type();

    if (type == typeid(db::null)) {
        sqlite3_bind_null(stmt, column_idx);
    } else if (type == typeid(db::blob)) {
        db::blob const &blob = value.get<db::blob>();
        void const *data = blob.data();
        if (!data) {
            data = "";
        }
        sqlite3_bind_blob(stmt, column_idx, data, static_cast<int>(blob.size()), SQLITE_STATIC);
    } else if (type == typeid(db::integer)) {
        sqlite3_bind_int64(stmt, column_idx, value.get<db::integer>());
    } else if (type == typeid(db::real)) {
        sqlite3_bind_double(stmt, column_idx, value.get<db::real>());
    } else if (type == typeid(db::text)) {
        sqlite3_bind_text(stmt, column_idx, value.get<db::text>().c_str(), -1, SQLITE_STATIC);
    }
}
}  // namespace yas::db

#pragma mark - database

std::string database::sqlite_lib_version() {
    return sqlite3_libversion();
}

bool database::sqlite_thread_safe() {
    return sqlite3_threadsafe() != 0;
}

database::database(std::string const &path) : _database_path(path) {
}

database::~database() {
    this->close();

    db::_databases.erase(this->_db_key);
}

std::string const &database::database_path() const {
    return this->_database_path;
}

sqlite3 *database::sqlite_handle() const {
    return this->_sqlite_handle;
}

bool database::open() {
    if (this->_sqlite_handle) {
        return true;
    }

    int err = sqlite3_open(this->_database_path.c_str(), &this->_sqlite_handle);
    if (err != SQLITE_OK) {
        return false;
    }

    this->_execute_update("pragma foreign_keys = ON;", {}, {});

    if (this->_max_busy_retry_time_interval > 0.0) {
        this->set_max_busy_retry_time_interval(this->_max_busy_retry_time_interval);
    }

    return true;
}

#if SQLITE_VERSION_NUMBER >= 3005000
bool database::open(int flags) {
    if (this->_sqlite_handle) {
        return true;
    }

    int err = sqlite3_open_v2(this->_database_path.c_str(), &this->_sqlite_handle, flags, NULL);
    if (err != SQLITE_OK) {
        return false;
    }

    if (this->_max_busy_retry_time_interval > 0.0) {
        this->set_max_busy_retry_time_interval(this->_max_busy_retry_time_interval);
    }

    return true;
}
#endif

void database::close() {
    this->clear_cached_statements();
    this->close_opened_row_sets();

    if (!this->_sqlite_handle) {
        return;
    }

    int result_code = 0;
    bool retry = false;
    bool tried_finalizing_open_statements = false;

    do {
        retry = false;
        result_code = sqlite3_close(this->_sqlite_handle);
        if (SQLITE_BUSY == result_code || SQLITE_LOCKED == result_code) {
            if (!tried_finalizing_open_statements) {
                tried_finalizing_open_statements = true;
                while (sqlite3_stmt *stmt = sqlite3_next_stmt(this->_sqlite_handle, nullptr)) {
                    sqlite3_finalize(stmt);
                    retry = true;
                }
            }
        } else if (SQLITE_OK != result_code) {
            //                NSLog(@"error closing!: %d", rc);
        }
    } while (retry);

    this->_sqlite_handle = nullptr;

    return;
}

bool database::good_connection() const {
    if (!this->_sqlite_handle) {
        return false;
    }

    if (db::query_result_t query_result = execute_query("select name from sqlite_master where type='table'")) {
        db::row_set_ptr const &row_set = query_result.value();
        if (db::closable_ptr const closable_rs = closable::cast(row_set)) {
            closable_rs->close();
        }
        return true;
    }

    return false;
}

db::integrity_result_t database::integrity_check() const {
    auto query_result = this->execute_query("pragma integrity_check;");
    if (query_result) {
        auto const &row_set = query_result.value();
        if (row_set->next()) {
            if (db::value value = row_set->column_value("integrity_check")) {
                std::string str_value = value.get<db::text>();
                if (to_lower(str_value) == "ok") {
                    return db::integrity_result_t{nullptr};
                }
            }
        }
        return db::integrity_result_t{""};
    } else {
        return db::integrity_result_t{query_result.error().message()};
    }
}

db::update_result_t database::execute_update(std::string const &sql) {
    return this->_execute_update(sql, {}, {});
}

db::update_result_t database::execute_update(std::string const &sql, std::vector<db::value> const &arguments) {
    return this->_execute_update(sql, arguments, {});
}

db::update_result_t database::execute_update(std::string const &sql,
                                             std::unordered_map<std::string, db::value> const &arguments) {
    return this->_execute_update(sql, {}, arguments);
}

db::update_result_t database::execute_statements(std::string const &sql) {
    return this->_execute_statements(sql, nullptr);
}

db::update_result_t database::execute_statements(std::string const &sql, callback_f const &callback) {
    return this->_execute_statements(sql, callback);
}

database::callback_f const &database::callback_for_execute_statements() const {
    return this->_callback_for_execute_statements;
}

db::query_result_t database::execute_query(std::string const &sql) const {
    return this->_execute_query(sql, {}, {});
}

db::query_result_t database::execute_query(std::string const &sql, value_vector_t const &arguments) const {
    return this->_execute_query(sql, arguments, {});
}

db::query_result_t database::execute_query(std::string const &sql, value_map_t const &arguments) const {
    return this->_execute_query(sql, {}, arguments);
}

db::row_result_t database::last_insert_rowid() const {
    if (this->_is_executing_statement) {
        return db::row_result_t{db::error{db::error_type::in_use}};
    }

    this->_is_executing_statement = true;

    sqlite_int64 rowid = sqlite3_last_insert_rowid(this->_sqlite_handle);

    this->_is_executing_statement = false;

    return db::row_result_t{rowid};
}

db::count_result_t database::changes() const {
    if (this->_is_executing_statement) {
        return db::count_result_t{db::error{db::error_type::in_use}};
    }

    this->_is_executing_statement = true;

    int changes = sqlite3_changes(this->_sqlite_handle);

    this->_is_executing_statement = false;

    return db::count_result_t{changes};
}

void database::clear_cached_statements() {
    for (auto &pair : this->_cached_statements) {
        for (auto &statement_pair : pair.second) {
            if (db::closable_ptr const statement = closable::cast(statement_pair.second)) {
                statement->close();
            }
        }
    }
    this->_cached_statements.clear();
}

void database::close_opened_row_sets() {
    for (auto &pair : this->_opened_row_sets) {
        if (db::row_set_ptr const row_set = pair.second.lock()) {
            db_settable::cast(row_set)->set_database(nullptr);
            closable::cast(row_set)->close();
        }
    }
    this->_opened_row_sets.clear();
}

bool database::has_opened_row_sets() const {
    return this->_opened_row_sets.size() > 0;
}

bool database::should_cache_statements() const {
    return this->_should_cache_statements;
}

void database::set_should_cache_statements(bool flag) {
    this->_should_cache_statements = flag;

    if (!flag) {
        this->_cached_statements.clear();
    }
}

std::string database::last_error_message() const {
    return sqlite3_errmsg(this->_sqlite_handle);
}

int database::last_error_code() const {
    return sqlite3_errcode(this->_sqlite_handle);
}

bool database::had_error() const {
    int code = this->last_error_code();
    return (code > SQLITE_OK && code < SQLITE_ROW);
}

void database::set_max_busy_retry_time_interval(double const timeout) {
    this->_max_busy_retry_time_interval = timeout;

    if (!this->_sqlite_handle) {
        return;
    }

    if (timeout > 0) {
        db::callback_id id{.database = this->_db_key};

        static auto sqlite_busy_handler = [](void *id, int count) {
            uint8_t const database_id = (db::callback_id){id}.database;
            if (db::_databases.count(database_id) > 0) {
                if (auto const database = db::_databases.at(database_id).lock()) {
                    if (count == 0) {
                        database->set_start_busy_retry_time(std::chrono::system_clock::now());
                        return 1;
                    }

                    std::chrono::duration<double> delta =
                        std::chrono::system_clock::now() - database->start_busy_retry_time();
                    if (delta.count() < database->max_busy_retry_time_interval()) {
                        sqlite3_sleep(50);
                        return 1;
                    }
                }
            }
            return 0;
        };

        sqlite3_busy_handler(this->_sqlite_handle, sqlite_busy_handler, id.v);
    } else {
        sqlite3_busy_handler(this->_sqlite_handle, nullptr, nullptr);
    }
}

double database::max_busy_retry_time_interval() const {
    return this->_max_busy_retry_time_interval;
}

void database::set_start_busy_retry_time(std::chrono::time_point<std::chrono::system_clock> const &time) {
    this->_start_busy_retry_time = time;
}

std::chrono::time_point<std::chrono::system_clock> database::start_busy_retry_time() const {
    return this->_start_busy_retry_time;
}

void database::_prepare(database_ptr const &shared) {
    this->_weak_database = shared;

    if (auto key = min_empty_key(db::_databases)) {
        this->_db_key = *key;
        db::_databases.insert(std::make_pair(*key, to_weak(shared)));
    }
}

db::update_result_t database::_execute_update(std::string const &sql, std::vector<db::value> const &vec,
                                              std::unordered_map<std::string, db::value> const &map) {
    if (!this->_database_exists()) {
        return db::update_result_t{db::error{db::error_type::closed}};
    }

    if (this->_is_executing_statement) {
        return db::update_result_t{db::error{db::error_type::in_use}};
    }

    this->_is_executing_statement = true;

    db::sqlite_result_code result_code{SQLITE_OK};
    std::string error_message;
    sqlite3_stmt *stmt = nullptr;
    db::statement_ptr statement{nullptr};

    if (this->_should_cache_statements) {
        statement = this->_cached_statement(sql);
        if (statement) {
            stmt = statement->stmt();
            statement->reset();
        }
    }

    if (!stmt) {
        result_code = sqlite3_prepare_v2(this->_sqlite_handle, sql.c_str(), -1, &stmt, 0);

        if (!result_code) {
            db::update_result_t result{db::error{db::error_type::sqlite, result_code, last_error_message()}};
            sqlite3_finalize(stmt);
            this->_is_executing_statement = false;
            return result;
        }
    }

    int idx = 0;
    int query_count = sqlite3_bind_parameter_count(stmt);

    if (map.size() == query_count) {
        for (auto &pair : map) {
            std::string parameter_name = ":" + pair.first;

            int named_idx = sqlite3_bind_parameter_index(stmt, parameter_name.c_str());
            if (named_idx > 0) {
                db::bind(pair.second, named_idx, stmt);
                ++idx;
            } else {
                //                NSLog(@"Could not find index for %@", dictionaryKey);
            }
        }
    } else if (vec.size() == query_count) {
        while (idx < query_count) {
            db::value const &value = vec.at(idx);

            ++idx;
            db::bind(value, idx, stmt);
        }
    }

    if (idx != query_count) {
        sqlite3_finalize(stmt);
        this->_is_executing_statement = false;
        return db::update_result_t{db::error{db::error_type::invalid_query_count}};
    }

    result_code = sqlite3_step(stmt);

    if (!result_code) {
        error_message = this->last_error_message();
    }

    if (result_code.raw_value() == SQLITE_ROW) {
        throw std::runtime_error(std::string(__PRETTY_FUNCTION__) +
                                 " : execute_update is being called with a query string '" + sql + "'.");
    }

    if (this->_should_cache_statements && !statement) {
        statement = db::statement::make_shared();
        statement->set_stmt(stmt);
        this->_set_cached_statement(statement, sql);
    }

    db::sqlite_result_code close_result_code;

    if (statement) {
        close_result_code = sqlite3_reset(stmt);
    } else {
        close_result_code = sqlite3_finalize(stmt);
    }

    if (!close_result_code && result_code) {
        result_code = close_result_code;
        error_message = this->last_error_message();
    }

    this->_is_executing_statement = false;

    if (result_code) {
        return db::update_result_t{nullptr};
    } else {
        return db::update_result_t{db::error{db::error_type::sqlite, result_code, error_message}};
    }
}

db::update_result_t database::_execute_statements(std::string const &sql, callback_f const &function) {
    db::callback_id callback_id{.database = this->_db_key};
    this->_callback_for_execute_statements = function;

    static auto execute_bulk_sql_callback = [](void *id, int columns, char **values, char **names) {
        auto database_id = (db::callback_id){id}.database;
        if (db::_databases.count(database_id) > 0) {
            if (database_ptr database = db::_databases.at(database_id).lock()) {
                std::unordered_map<std::string, db::value> map;
                auto each = make_fast_each(columns);
                while (yas_each_next(each)) {
                    int const &idx = yas_each_index(each);
                    char const *const name = names[idx];
                    char const *const value = values[idx];
                    if (name) {
                        if (value) {
                            map.insert(std::make_pair(name, db::value{value}));
                        } else {
                            map.insert(std::make_pair(name, db::null_value()));
                        }
                    }
                }

                if (callback_f const &callback = database->callback_for_execute_statements()) {
                    return callback(map);
                }
            }
        }

        return 0;
    };

    char *errmsg = nullptr;

    db::sqlite_result_code result_code = sqlite3_exec(
        this->_sqlite_handle, sql.c_str(), function ? execute_bulk_sql_callback : nullptr, callback_id.v, &errmsg);

    this->_callback_for_execute_statements = nullptr;

    std::string error_message;
    if (errmsg) {
        error_message = errmsg;
        sqlite3_free(errmsg);
    }

    if (result_code) {
        return db::update_result_t{nullptr};
    } else {
        return db::update_result_t{db::error{db::error_type::sqlite, result_code, error_message}};
    }
}

db::query_result_t database::_execute_query(std::string const &sql, value_vector_t const &vec,
                                            value_map_t const &map) const {
    if (!this->_database_exists()) {
        return db::query_result_t{db::error{db::error_type::closed}};
    }

    if (this->_is_executing_statement) {
        return db::query_result_t{db::error{db::error_type::in_use}};
    }

    this->_is_executing_statement = true;

    db::sqlite_result_code result_code = 0;
    std::string error_message;
    sqlite3_stmt *stmt{nullptr};
    statement_ptr statement{nullptr};
    row_set_ptr row_set{nullptr};

    if (this->_should_cache_statements) {
        statement = this->_cached_statement(sql);
        if (statement) {
            stmt = statement->stmt();
            statement->reset();
        }
    }

    if (!stmt) {
        result_code = sqlite3_prepare_v2(this->_sqlite_handle, sql.c_str(), -1, &stmt, 0);

        if (!result_code) {
            db::query_result_t result{db::error{db::error_type::sqlite, result_code, last_error_message()}};
            sqlite3_finalize(stmt);
            this->_is_executing_statement = false;
            return result;
        }
    }

    std::vector<db::value> context;
    int idx = 0;
    int query_count = sqlite3_bind_parameter_count(stmt);

    if (map.size() == query_count) {
        context.reserve(map.size());

        for (auto &pair : map) {
            std::string parameter_name = ":" + pair.first;
            int named_idx = sqlite3_bind_parameter_index(stmt, parameter_name.c_str());
            if (named_idx > 0) {
                db::bind(pair.second, named_idx, stmt);
                ++idx;
                context.push_back(pair.second);
            } else {
                error_message = "could not find index for '" + parameter_name + "'.";
            }
        }
    } else if (vec.size() == query_count) {
        while (idx < query_count) {
            db::value const &value = vec.at(idx);
            ++idx;
            db::bind(value, idx, stmt);
        }
        context = vec;
    }

    if (idx != query_count) {
        sqlite3_finalize(stmt);
        this->_is_executing_statement = false;
        return db::query_result_t{db::error{db::error_type::invalid_query_count, 0, error_message}};
    }

    if (!statement) {
        statement = db::statement::make_shared();
        statement->set_stmt(stmt);

        if (this->_should_cache_statements && sql.size() > 0) {
            this->_set_cached_statement(statement, sql);
        }
    }

    row_set = db::row_set::make_shared(statement, this->_weak_database.lock(), context);

    this->_opened_row_sets.insert(std::make_pair(row_set->identifier(), row_set));

    this->_is_executing_statement = false;

    return db::query_result_t{std::move(row_set)};
}

bool database::_database_exists() const {
    return this->_sqlite_handle;
}

db::statement_ptr database::_cached_statement(std::string const &query) const {
    if (this->_cached_statements.count(query) > 0) {
        auto &statements = this->_cached_statements.at(query);
        for (auto &pair : statements) {
            if (!pair.second->in_use()) {
                return pair.second;
            }
        }
    }
    return nullptr;
}

void database::_set_cached_statement(db::statement_ptr const &statement, std::string const &query) const {
    statement->set_query(query);

    if (this->_cached_statements.count(query) == 0) {
        this->_cached_statements.insert(std::make_pair(query, std::unordered_map<uintptr_t, db::statement_ptr>{}));
    }

    this->_cached_statements.at(query).insert(std::make_pair(statement->identifier(), statement));
}

void database::row_set_did_close(uintptr_t const id) {
    this->_opened_row_sets.erase(id);
}

database_ptr database::make_shared(std::string const &path) {
    auto shared = std::shared_ptr<database>(new database{path});
    shared->_prepare(shared);
    return shared;
}
