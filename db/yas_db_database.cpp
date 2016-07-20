//
//  yas_db_database.cpp
//

#include <mutex>
#include "yas_db_database.h"
#include "yas_db_row_set.h"
#include "yas_db_statement.h"
#include "yas_db_value.h"
#include "yas_each_index.h"
#include "yas_result.h"
#include "yas_stl_utils.h"

using namespace yas;

namespace yas {
namespace db {
    static std::map<uint8_t, weak<database>> _databases;
}
}

#pragma mark - code

db::sqlite_result_code::sqlite_result_code(int const &value) : result_code(value) {
}

db::sqlite_result_code::operator bool() const {
    auto value = raw_value();
    return value == SQLITE_OK || value == SQLITE_DONE;
}

#pragma mark - error

db::error::error(std::nullptr_t) : _type(error_type::none), _code(0), _message() {
}

db::error::error(error_type const type, sqlite_result_code const &code, std::string message)
    : _type(type), _code(code), _message(std::move(message)) {
}

db::error::operator bool() const {
    return _type != error_type::none;
}

db::error_type const &db::error::type() const {
    return _type;
}

db::sqlite_result_code const &db::error::code() const {
    return _code;
}

std::string const &db::error::message() const {
    return _message;
}

#pragma mark - impl

class db::database::impl : public base::impl, public row_set_observable::impl {
   public:
    uint8_t db_key;
    std::string database_path;
    sqlite3 *sqlite_handle = nullptr;

    bool should_cache_statements = false;
    bool is_executing_statement = false;

    std::chrono::time_point<std::chrono::system_clock> start_busy_retry_time = std::chrono::system_clock::now();

    std::unordered_map<std::string, std::unordered_map<uintptr_t, db::statement>> cached_statements;
    std::unordered_map<uintptr_t, weak<row_set>> open_row_sets;

    callback_function callback_for_execute_statements;

    impl(std::string const &path) : database_path(path) {
    }

    ~impl() {
        close();

        _databases.erase(db_key);
    }

    const char *sqlite_path() const {
        return database_path.c_str();
    }

    bool open() {
        if (sqlite_handle) {
            return true;
        }

        int err = sqlite3_open(sqlite_path(), &sqlite_handle);
        if (err != SQLITE_OK) {
            return false;
        }

        execute_update("pragma foreign_keys = ON;", {}, {});

        if (_max_busy_retry_time_interval > 0.0) {
            set_max_busy_retry_time_interval(_max_busy_retry_time_interval);
        }

        return true;
    }

    bool open(int flags) {
        if (sqlite_handle) {
            return true;
        }

        int err = sqlite3_open_v2(sqlite_path(), &sqlite_handle, flags, NULL);
        if (err != SQLITE_OK) {
            return false;
        }

        if (_max_busy_retry_time_interval > 0.0) {
            set_max_busy_retry_time_interval(_max_busy_retry_time_interval);
        }

        return true;
    }

    bool close() {
        clear_cached_statements();
        close_open_row_sets();

        if (!sqlite_handle) {
            return true;
        }

        int result_code = 0;
        bool retry = false;
        bool tried_finalizing_open_statements = false;

        do {
            retry = false;
            result_code = sqlite3_close(sqlite_handle);
            if (SQLITE_BUSY == result_code || SQLITE_LOCKED == result_code) {
                if (!tried_finalizing_open_statements) {
                    tried_finalizing_open_statements = true;
                    while (auto stmt = sqlite3_next_stmt(sqlite_handle, nullptr)) {
                        sqlite3_finalize(stmt);
                        retry = true;
                    }
                }
            } else if (SQLITE_OK != result_code) {
                //                NSLog(@"error closing!: %d", rc);
            }
        } while (retry);

        sqlite_handle = nullptr;

        return true;
    }

    std::string last_error_message() const {
        return sqlite3_errmsg(sqlite_handle);
    }

    int last_error_code() const {
        return sqlite3_errcode(sqlite_handle);
    }

    bool had_error() const {
        int code = last_error_code();
        return (code > SQLITE_OK && code < SQLITE_ROW);
    }

#pragma mark - private

    db::statement cached_statement(std::string const &query) {
        if (cached_statements.count(query) > 0) {
            auto &statements = cached_statements.at(query);
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

        if (cached_statements.count(query) == 0) {
            cached_statements.insert(std::make_pair(query, std::unordered_map<uintptr_t, db::statement>{}));
        }

        cached_statements.at(query).insert(std::make_pair(statement.identifier(), statement));
    }

    void clear_cached_statements() {
        for (auto &pair : cached_statements) {
            for (auto &statementpair : pair.second) {
                if (auto statement = statementpair.second.closable()) {
                    statement.close();
                }
            }
        }
        cached_statements.clear();
    }

    void close_open_row_sets() {
        for (auto &pair : open_row_sets) {
            if (auto row_set = pair.second.lock()) {
                row_set.db_settable().set_database(nullptr);
                row_set.closable().close();
            }
        }
        open_row_sets.clear();
    }

    bool database_exists() const {
        return sqlite_handle;
    }

    static void bind(value const &value, int column_idx, sqlite3_stmt *stmt) {
        std::type_info const &type = value.type();

        if (type == typeid(db::null)) {
            sqlite3_bind_null(stmt, column_idx);
        } else if (type == typeid(db::blob)) {
            auto const &blob = value.get<db::blob>();
            const void *data = blob.data();
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

    update_result execute_update(std::string const &sql, std::vector<db::value> const &vec,
                                 std::unordered_map<std::string, db::value> const &map) {
        if (!database_exists()) {
            return update_result{error{error_type::closed}};
        }

        if (is_executing_statement) {
            return update_result{error{error_type::in_use}};
        }

        is_executing_statement = true;

        sqlite_result_code result_code{SQLITE_OK};
        std::string error_message;
        sqlite3_stmt *stmt = nullptr;
        db::statement statement{nullptr};

        if (should_cache_statements) {
            statement = cached_statement(sql);
            if (statement) {
                stmt = statement.stmt();
                statement.reset();
            }
        }

        if (!stmt) {
            result_code = sqlite3_prepare_v2(sqlite_handle, sql.c_str(), -1, &stmt, 0);

            if (!result_code) {
                auto result = update_result{error{error_type::sqlite, result_code, last_error_message()}};
                sqlite3_finalize(stmt);
                is_executing_statement = false;
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
                    //                NSLog(@"Could not find index for %@", dictionaryKey);
                }
            }
        } else if (vec.size() == query_count) {
            while (idx < query_count) {
                auto &value = vec.at(idx);

                ++idx;
                bind(value, idx, stmt);
            }
        }

        if (idx != query_count) {
            sqlite3_finalize(stmt);
            is_executing_statement = false;
            return update_result{error{error_type::invalid_query_count}};
        }

        result_code = sqlite3_step(stmt);

        if (!result_code) {
            error_message = last_error_message();
        }

        if (result_code.raw_value() == SQLITE_ROW) {
            throw std::runtime_error(std::string(__PRETTY_FUNCTION__) +
                                     " : execute_update is being called with a query string '" + sql + "'.");
        }

        if (should_cache_statements && !statement) {
            statement = db::statement{};
            statement.set_stmt(stmt);
            set_cached_statement(statement, sql);
        }

        sqlite_result_code close_result_code;

        if (statement) {
            close_result_code = sqlite3_reset(stmt);
        } else {
            close_result_code = sqlite3_finalize(stmt);
        }

        if (!close_result_code && result_code) {
            result_code = close_result_code;
            error_message = last_error_message();
        }

        is_executing_statement = false;

        if (result_code) {
            return update_result{nullptr};
        } else {
            return update_result{error{error_type::sqlite, result_code, error_message}};
        }
    }

    update_result execute_statements(std::string const &sql, callback_function const &function) {
        callback_id callback_id{.database = db_key};
        callback_for_execute_statements = function;

        static auto execute_bulk_sql_callback = [](void *id, int columns, char **values, char **names) {
            auto database_id = (db::callback_id){id}.database;
            if (db::_databases.count(database_id) > 0) {
                if (auto database = db::_databases.at(database_id).lock()) {
                    std::unordered_map<std::string, db::value> map;
                    for (auto &idx : make_each(columns)) {
                        auto const &name = names[idx];
                        auto const &value = values[idx];
                        if (name) {
                            if (value) {
                                map.insert(std::make_pair(name, db::value{value}));
                            } else {
                                map.insert(std::make_pair(name, db::value{nullptr}));
                            }
                        }
                    }

                    if (auto &callback = database.callback_for_execute_statements()) {
                        return callback(map);
                    }
                }
            }

            return 0;
        };

        char *errmsg = nullptr;

        sqlite_result_code result_code = sqlite3_exec(
            sqlite_handle, sql.c_str(), function ? execute_bulk_sql_callback : nullptr, callback_id.v, &errmsg);

        callback_for_execute_statements = nullptr;

        std::string error_message;
        if (errmsg) {
            error_message = errmsg;
            sqlite3_free(errmsg);
        }

        if (result_code) {
            return update_result{nullptr};
        } else {
            return update_result{error{error_type::sqlite, result_code, error_message}};
        }
    }

    db::query_result execute_query(std::string const &sql, value_vector const &vec, value_map const &map) {
        if (!database_exists()) {
            return query_result{error{error_type::closed}};
        }

        if (is_executing_statement) {
            return query_result{error{error_type::in_use}};
        }

        is_executing_statement = true;

        sqlite_result_code result_code = 0;
        std::string error_message;
        sqlite3_stmt *stmt{nullptr};
        statement statement{nullptr};
        row_set row_set{nullptr};

        if (should_cache_statements) {
            statement = cached_statement(sql);
            if (statement) {
                stmt = statement.stmt();
                statement.reset();
            }
        }

        if (!stmt) {
            result_code = sqlite3_prepare_v2(sqlite_handle, sql.c_str(), -1, &stmt, 0);

            if (!result_code) {
                auto result = query_result{error{error_type::sqlite, result_code, last_error_message()}};
                sqlite3_finalize(stmt);
                is_executing_statement = false;
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
                auto &value = vec.at(idx);
                ++idx;
                bind(value, idx, stmt);
            }
        }

        if (idx != query_count) {
            sqlite3_finalize(stmt);
            is_executing_statement = false;
            return query_result{error{error_type::invalid_query_count, 0, error_message}};
        }

        if (!statement) {
            statement = db::statement{};
            statement.set_stmt(stmt);

            if (should_cache_statements && sql.size() > 0) {
                set_cached_statement(statement, sql);
            }
        }

        row_set = db::row_set{statement, cast<db::database>()};

        open_row_sets.insert(std::make_pair(row_set.identifier(), row_set));

        is_executing_statement = false;

        return query_result{std::move(row_set)};
    }

    row_result last_insert_row_id() {
        if (is_executing_statement) {
            return row_result{error{error_type::in_use}};
        }

        is_executing_statement = true;

        sqlite_int64 row_id = sqlite3_last_insert_rowid(sqlite_handle);

        is_executing_statement = false;

        return row_result{row_id};
    }

    count_result changes() {
        if (is_executing_statement) {
            return count_result{error{error_type::in_use}};
        }

        is_executing_statement = true;

        int changes = sqlite3_changes(sqlite_handle);

        is_executing_statement = false;

        return count_result{changes};
    }

    void set_max_busy_retry_time_interval(double const timeout) {
        _max_busy_retry_time_interval = timeout;

        if (!sqlite_handle) {
            return;
        }

        if (timeout > 0) {
            callback_id id{.database = db_key};

            static auto sqlite_busy_handler = [](void *id, int count) {
                auto database_id = (db::callback_id){id}.database;
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

            sqlite3_busy_handler(sqlite_handle, sqlite_busy_handler, id.v);
        } else {
            sqlite3_busy_handler(sqlite_handle, nullptr, nullptr);
        }
    }

    double max_busy_retry_time_interval() const {
        return _max_busy_retry_time_interval;
    }

    void _row_set_did_close(uintptr_t const id) override {
        open_row_sets.erase(id);
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
    if (auto key = min_empty_key(_databases)) {
        impl_ptr<impl>()->db_key = *key;
        db::_databases.insert(std::make_pair(*key, *this));
    }
}

db::database::database(std::nullptr_t) : base(nullptr) {
}

db::database::~database() = default;

std::string const &db::database::database_path() const {
    return impl_ptr<impl>()->database_path;
}

sqlite3 *db::database::sqlite_handle() const {
    return impl_ptr<impl>()->sqlite_handle;
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
    if (!impl_ptr<impl>()->sqlite_handle) {
        return false;
    }

    if (auto query_result = execute_query("select name from sqlite_master where type='table'")) {
        auto &row_set = query_result.value();
        if (auto closable_rs = row_set.closable()) {
            closable_rs.close();
        }
        return true;
    }

    return false;
}

db::update_result db::database::execute_update(std::string const &sql) {
    return impl_ptr<impl>()->execute_update(sql, {}, {});
}

db::update_result db::database::execute_update(std::string const &sql, std::vector<db::value> const &arguments) {
    return impl_ptr<impl>()->execute_update(sql, arguments, {});
}

db::update_result db::database::execute_update(std::string const &sql,
                                               std::unordered_map<std::string, db::value> const &arguments) {
    return impl_ptr<impl>()->execute_update(sql, {}, arguments);
}

db::update_result db::database::execute_statements(std::string const &sql) {
    return impl_ptr<impl>()->execute_statements(sql, nullptr);
}

db::update_result db::database::execute_statements(std::string const &sql, callback_function const &callback) {
    return impl_ptr<impl>()->execute_statements(sql, callback);
}

db::database::callback_function const &db::database::callback_for_execute_statements() const {
    return impl_ptr<impl>()->callback_for_execute_statements;
}

db::query_result db::database::execute_query(std::string const &sql) const {
    return impl_ptr<impl>()->execute_query(sql, {}, {});
}

db::query_result db::database::execute_query(std::string const &sql, value_vector const &arguments) const {
    return impl_ptr<impl>()->execute_query(sql, arguments, {});
}

db::query_result db::database::execute_query(std::string const &sql, value_map const &arguments) const {
    return impl_ptr<impl>()->execute_query(sql, {}, arguments);
}

db::row_result db::database::last_insert_row_id() const {
    return impl_ptr<impl>()->last_insert_row_id();
}

db::count_result db::database::changes() const {
    return impl_ptr<impl>()->changes();
}

void db::database::clear_cached_statements() {
    impl_ptr<impl>()->clear_cached_statements();
}

void db::database::close_open_row_sets() {
    impl_ptr<impl>()->close_open_row_sets();
}

bool db::database::has_open_row_sets() const {
    return impl_ptr<impl>()->open_row_sets.size() > 0;
}

bool db::database::should_cache_statements() const {
    return impl_ptr<impl>()->should_cache_statements;
}

void db::database::set_should_cache_statements(bool flag) {
    impl_ptr<impl>()->should_cache_statements = flag;

    if (!flag) {
        impl_ptr<impl>()->cached_statements.clear();
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
    impl_ptr<impl>()->start_busy_retry_time = time;
}

std::chrono::time_point<std::chrono::system_clock> db::database::start_busy_retry_time() const {
    return impl_ptr<impl>()->start_busy_retry_time;
}

db::row_set_observable &db::database::row_set_observable() {
    if (!_row_set_observable) {
        _row_set_observable = db::row_set_observable{impl_ptr<row_set_observable::impl>()};
    }
    return _row_set_observable;
}

#pragma mark -

std::string yas::to_string(db::error_type const &error_type) {
    switch (error_type) {
        case db::error_type::closed:
            return "closed";
        case db::error_type::in_use:
            return "in_use";
        case db::error_type::invalid_query_count:
            return "invalid_query_count";
        case db::error_type::invalid_argument:
            return "invalid_argument";
        case db::error_type::sqlite:
            return "sqlite";
        case db::error_type::none:
            return "none";
    }
    return std::string();
}
