//
//  yas_db_database.cpp
//

#include <mutex>
#include "yas_db_database.h"
#include "yas_db_row_set.h"
#include "yas_db_statement.h"
#include "yas_db_value.h"
#include "yas_db_error.h"
#include "yas_fast_each.h"
#include "yas_result.h"
#include "yas_stl_utils.h"

using namespace yas;

namespace yas {
namespace db {
    static std::map<uint8_t, weak<database>> _databases;
}
}

#pragma mark - impl

struct db::database::impl : base::impl, row_set_observable::impl {
    uint8_t _db_key;
    std::string _database_path;
    sqlite3 *_sqlite_handle = nullptr;

    bool _should_cache_statements = false;
    bool _is_executing_statement = false;

    std::chrono::time_point<std::chrono::system_clock> _start_busy_retry_time = std::chrono::system_clock::now();

    std::unordered_map<std::string, std::unordered_map<uintptr_t, db::statement>> _cached_statements;
    std::unordered_map<uintptr_t, weak<row_set>> _open_row_sets;

    db::database::callback_f _callback_for_execute_statements;

    impl(std::string const &path) : _database_path(path) {
    }

    ~impl() {
        this->close();

        db::_databases.erase(_db_key);
    }

    const char *sqlite_path() const {
        return this->_database_path.c_str();
    }

    bool open() {
        if (this->_sqlite_handle) {
            return true;
        }

        int err = sqlite3_open(this->sqlite_path(), &this->_sqlite_handle);
        if (err != SQLITE_OK) {
            return false;
        }

        this->execute_update("pragma foreign_keys = ON;", {}, {});

        if (this->_max_busy_retry_time_interval > 0.0) {
            this->set_max_busy_retry_time_interval(this->_max_busy_retry_time_interval);
        }

        return true;
    }

    bool open(int flags) {
        if (this->_sqlite_handle) {
            return true;
        }

        int err = sqlite3_open_v2(this->sqlite_path(), &this->_sqlite_handle, flags, NULL);
        if (err != SQLITE_OK) {
            return false;
        }

        if (this->_max_busy_retry_time_interval > 0.0) {
            this->set_max_busy_retry_time_interval(this->_max_busy_retry_time_interval);
        }

        return true;
    }

    bool close() {
        this->clear_cached_statements();
        this->close_open_row_sets();

        if (!this->_sqlite_handle) {
            return true;
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

        return true;
    }

    std::string last_error_message() const {
        return sqlite3_errmsg(this->_sqlite_handle);
    }

    int last_error_code() const {
        return sqlite3_errcode(this->_sqlite_handle);
    }

    bool had_error() const {
        int code = this->last_error_code();
        return (code > SQLITE_OK && code < SQLITE_ROW);
    }

#pragma mark - private

    db::statement cached_statement(std::string const &query) {
        if (this->_cached_statements.count(query) > 0) {
            auto &statements = this->_cached_statements.at(query);
            for (auto &pair : statements) {
                if (!pair.second.in_use()) {
                    return pair.second;
                }
            }
        }
        return nullptr;
    }

    void set_cached_statement(db::statement const &statement, std::string const &query) {
        db::statement cached_statement = statement;
        cached_statement.set_query(query);

        if (this->_cached_statements.count(query) == 0) {
            this->_cached_statements.insert(std::make_pair(query, std::unordered_map<uintptr_t, db::statement>{}));
        }

        _cached_statements.at(query).insert(std::make_pair(statement.identifier(), statement));
    }

    void clear_cached_statements() {
        for (auto &pair : this->_cached_statements) {
            for (auto &statementpair : pair.second) {
                if (db::closable &statement = statementpair.second.closable()) {
                    statement.close();
                }
            }
        }
        this->_cached_statements.clear();
    }

    void close_open_row_sets() {
        for (auto &pair : this->_open_row_sets) {
            if (db::row_set row_set = pair.second.lock()) {
                row_set.db_settable().set_database(nullptr);
                row_set.closable().close();
            }
        }
        this->_open_row_sets.clear();
    }

    bool database_exists() const {
        return this->_sqlite_handle;
    }

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

    db::update_result_t execute_update(std::string const &sql, std::vector<db::value> const &vec,
                                       std::unordered_map<std::string, db::value> const &map) {
        if (!this->database_exists()) {
            return db::update_result_t{db::error{db::error_type::closed}};
        }

        if (this->_is_executing_statement) {
            return db::update_result_t{db::error{db::error_type::in_use}};
        }

        this->_is_executing_statement = true;

        db::sqlite_result_code result_code{SQLITE_OK};
        std::string error_message;
        sqlite3_stmt *stmt = nullptr;
        db::statement statement{nullptr};

        if (this->_should_cache_statements) {
            statement = cached_statement(sql);
            if (statement) {
                stmt = statement.stmt();
                statement.reset();
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
                    this->bind(pair.second, named_idx, stmt);
                    ++idx;
                } else {
                    //                NSLog(@"Could not find index for %@", dictionaryKey);
                }
            }
        } else if (vec.size() == query_count) {
            while (idx < query_count) {
                db::value const &value = vec.at(idx);

                ++idx;
                this->bind(value, idx, stmt);
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
            statement = db::statement{};
            statement.set_stmt(stmt);
            this->set_cached_statement(statement, sql);
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

    db::update_result_t execute_statements(std::string const &sql, callback_f const &function) {
        db::callback_id callback_id{.database = _db_key};
        this->_callback_for_execute_statements = function;

        static auto execute_bulk_sql_callback = [](void *id, int columns, char **values, char **names) {
            auto database_id = (db::callback_id){id}.database;
            if (db::_databases.count(database_id) > 0) {
                if (db::database database = db::_databases.at(database_id).lock()) {
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

                    if (callback_f const &callback = database.callback_for_execute_statements()) {
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

    db::query_result_t execute_query(std::string const &sql, value_vector_t const &vec, value_map_t const &map) {
        if (!this->database_exists()) {
            return db::query_result_t{db::error{db::error_type::closed}};
        }

        if (this->_is_executing_statement) {
            return db::query_result_t{db::error{db::error_type::in_use}};
        }

        this->_is_executing_statement = true;

        db::sqlite_result_code result_code = 0;
        std::string error_message;
        sqlite3_stmt *stmt{nullptr};
        statement statement{nullptr};
        row_set row_set{nullptr};

        if (this->_should_cache_statements) {
            statement = this->cached_statement(sql);
            if (statement) {
                stmt = statement.stmt();
                statement.reset();
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

        int idx = 0;
        int query_count = sqlite3_bind_parameter_count(stmt);

        if (map.size() == query_count) {
            for (auto &pair : map) {
                std::string parameter_name = ":" + pair.first;
                int named_idx = sqlite3_bind_parameter_index(stmt, parameter_name.c_str());
                if (named_idx > 0) {
                    bind(pair.second, named_idx, stmt);
                    ++idx;
                } else {
                    error_message = "could not find index for '" + parameter_name + "'.";
                }
            }
        } else if (vec.size() == query_count) {
            while (idx < query_count) {
                db::value const &value = vec.at(idx);
                ++idx;
                bind(value, idx, stmt);
            }
        }

        if (idx != query_count) {
            sqlite3_finalize(stmt);
            this->_is_executing_statement = false;
            return db::query_result_t{db::error{db::error_type::invalid_query_count, 0, error_message}};
        }

        if (!statement) {
            statement = db::statement{};
            statement.set_stmt(stmt);

            if (this->_should_cache_statements && sql.size() > 0) {
                this->set_cached_statement(statement, sql);
            }
        }

        row_set = db::row_set{statement, cast<db::database>()};

        this->_open_row_sets.insert(std::make_pair(row_set.identifier(), row_set));

        this->_is_executing_statement = false;

        return db::query_result_t{std::move(row_set)};
    }

    db::row_result_t last_insert_rowid() {
        if (this->_is_executing_statement) {
            return db::row_result_t{db::error{db::error_type::in_use}};
        }

        this->_is_executing_statement = true;

        sqlite_int64 rowid = sqlite3_last_insert_rowid(this->_sqlite_handle);

        this->_is_executing_statement = false;

        return db::row_result_t{rowid};
    }

    db::count_result_t changes() {
        if (this->_is_executing_statement) {
            return db::count_result_t{db::error{db::error_type::in_use}};
        }

        this->_is_executing_statement = true;

        int changes = sqlite3_changes(this->_sqlite_handle);

        this->_is_executing_statement = false;

        return db::count_result_t{changes};
    }

    void set_max_busy_retry_time_interval(double const timeout) {
        this->_max_busy_retry_time_interval = timeout;

        if (!this->_sqlite_handle) {
            return;
        }

        if (timeout > 0) {
            db::callback_id id{.database = _db_key};

            static auto sqlite_busy_handler = [](void *id, int count) {
                uint8_t const database_id = (db::callback_id){id}.database;
                if (db::_databases.count(database_id) > 0) {
                    if (auto database = db::_databases.at(database_id).lock()) {
                        if (count == 0) {
                            database.set_start_busy_retry_time(std::chrono::system_clock::now());
                            return 1;
                        }

                        std::chrono::duration<double> delta =
                            std::chrono::system_clock::now() - database.start_busy_retry_time();
                        if (delta.count() < database.max_busy_retry_time_interval()) {
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

    double max_busy_retry_time_interval() const {
        return this->_max_busy_retry_time_interval;
    }

    void _row_set_did_close(uintptr_t const id) override {
        this->_open_row_sets.erase(id);
    }

   private:
    double _max_busy_retry_time_interval = 2.0;
};

#pragma mark - db::database

std::string db::database::sqlite_lib_version() {
    return sqlite3_libversion();
}

bool db::database::sqlite_thread_safe() {
    return sqlite3_threadsafe() != 0;
}

db::database::database(std::string const &path) : base(std::make_shared<impl>(path)) {
    if (auto key = min_empty_key(db::_databases)) {
        impl_ptr<impl>()->_db_key = *key;
        db::_databases.insert(std::make_pair(*key, *this));
    }
}

db::database::database(std::nullptr_t) : base(nullptr) {
}

db::database::~database() = default;

std::string const &db::database::database_path() const {
    return impl_ptr<impl>()->_database_path;
}

sqlite3 *db::database::sqlite_handle() const {
    return impl_ptr<impl>()->_sqlite_handle;
}

bool db::database::open() {
    return impl_ptr<impl>()->open();
}

#if SQLITE_VERSION_NUMBER >= 3005000
bool db::database::open(int flags) {
    return impl_ptr<impl>()->open(flags);
}
#endif

void db::database::close() {
    impl_ptr<impl>()->close();
}

bool db::database::good_connection() {
    if (!impl_ptr<impl>()->_sqlite_handle) {
        return false;
    }

    if (db::query_result_t query_result = execute_query("select name from sqlite_master where type='table'")) {
        db::row_set &row_set = query_result.value();
        if (db::closable &closable_rs = row_set.closable()) {
            closable_rs.close();
        }
        return true;
    }

    return false;
}

db::update_result_t db::database::execute_update(std::string const &sql) {
    return impl_ptr<impl>()->execute_update(sql, {}, {});
}

db::update_result_t db::database::execute_update(std::string const &sql, std::vector<db::value> const &arguments) {
    return impl_ptr<impl>()->execute_update(sql, arguments, {});
}

db::update_result_t db::database::execute_update(std::string const &sql,
                                                 std::unordered_map<std::string, db::value> const &arguments) {
    return impl_ptr<impl>()->execute_update(sql, {}, arguments);
}

db::update_result_t db::database::execute_statements(std::string const &sql) {
    return impl_ptr<impl>()->execute_statements(sql, nullptr);
}

db::update_result_t db::database::execute_statements(std::string const &sql, callback_f const &callback) {
    return impl_ptr<impl>()->execute_statements(sql, callback);
}

db::database::callback_f const &db::database::callback_for_execute_statements() const {
    return impl_ptr<impl>()->_callback_for_execute_statements;
}

db::query_result_t db::database::execute_query(std::string const &sql) const {
    return impl_ptr<impl>()->execute_query(sql, {}, {});
}

db::query_result_t db::database::execute_query(std::string const &sql, value_vector_t const &arguments) const {
    return impl_ptr<impl>()->execute_query(sql, arguments, {});
}

db::query_result_t db::database::execute_query(std::string const &sql, value_map_t const &arguments) const {
    return impl_ptr<impl>()->execute_query(sql, {}, arguments);
}

db::row_result_t db::database::last_insert_rowid() const {
    return impl_ptr<impl>()->last_insert_rowid();
}

db::count_result_t db::database::changes() const {
    return impl_ptr<impl>()->changes();
}

void db::database::clear_cached_statements() {
    impl_ptr<impl>()->clear_cached_statements();
}

void db::database::close_open_row_sets() {
    impl_ptr<impl>()->close_open_row_sets();
}

bool db::database::has_open_row_sets() const {
    return impl_ptr<impl>()->_open_row_sets.size() > 0;
}

bool db::database::should_cache_statements() const {
    return impl_ptr<impl>()->_should_cache_statements;
}

void db::database::set_should_cache_statements(bool flag) {
    impl_ptr<impl>()->_should_cache_statements = flag;

    if (!flag) {
        impl_ptr<impl>()->_cached_statements.clear();
    }
}

std::string db::database::last_error_message() const {
    return impl_ptr<impl>()->last_error_message();
}

int db::database::last_error_code() const {
    return impl_ptr<impl>()->last_error_code();
}

bool db::database::had_error() const {
    return impl_ptr<impl>()->had_error();
}

void db::database::set_max_busy_retry_time_interval(double const timeout) {
    impl_ptr<impl>()->set_max_busy_retry_time_interval(timeout);
}

double db::database::max_busy_retry_time_interval() const {
    return impl_ptr<impl>()->max_busy_retry_time_interval();
}

void db::database::set_start_busy_retry_time(std::chrono::time_point<std::chrono::system_clock> const &time) {
    impl_ptr<impl>()->_start_busy_retry_time = time;
}

std::chrono::time_point<std::chrono::system_clock> db::database::start_busy_retry_time() const {
    return impl_ptr<impl>()->_start_busy_retry_time;
}

db::row_set_observable &db::database::row_set_observable() {
    if (!this->_row_set_observable) {
        this->_row_set_observable = db::row_set_observable{impl_ptr<row_set_observable::impl>()};
    }
    return this->_row_set_observable;
}
