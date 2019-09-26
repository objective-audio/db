//
//  yas_db_database.h
//

#pragma once

#include <functional>
#include "yas_db_protocol.h"
#include "yas_db_ptr.h"
#include "yas_db_value.h"

namespace yas::db {
class error;

union callback_id {
    void *v;
    struct {
        uint8_t database;
    };
};

struct database final : row_set_observable {
    class impl;

    using callback_f = std::function<int(db::value_map_t const &)>;

    static std::string sqlite_lib_version();
    static bool sqlite_thread_safe();

    ~database() = default;

    std::string const &database_path() const;
    sqlite3 *sqlite_handle() const;

    bool open();
#if SQLITE_VERSION_NUMBER >= 3005000
    bool open(int flags);
#endif
    void close();
    bool good_connection() const;
    db::integrity_result_t integrity_check() const;

    db::update_result_t execute_update(std::string const &sql);
    db::update_result_t execute_update(std::string const &sql, db::value_vector_t const &arguments);
    db::update_result_t execute_update(std::string const &sql, db::value_map_t const &arguments);

    db::update_result_t execute_statements(std::string const &sql);
    db::update_result_t execute_statements(std::string const &sql, callback_f const &callback);
    callback_f const &callback_for_execute_statements() const;

    db::query_result_t execute_query(std::string const &sql) const;
    db::query_result_t execute_query(std::string const &sql, db::value_vector_t const &arguments) const;
    db::query_result_t execute_query(std::string const &sql, db::value_map_t const &arguments) const;

    db::row_result_t last_insert_rowid() const;
    db::count_result_t changes() const;

    void clear_cached_statements();
    void close_open_row_sets();
    bool has_open_row_sets() const;
    bool should_cache_statements() const;
    void set_should_cache_statements(bool flag);

    std::string last_error_message() const;
    int last_error_code() const;
    bool had_error() const;
    void set_max_busy_retry_time_interval(double const);
    double max_busy_retry_time_interval() const;
    void set_start_busy_retry_time(const std::chrono::time_point<std::chrono::system_clock> &time);
    std::chrono::time_point<std::chrono::system_clock> start_busy_retry_time() const;

    static database_ptr make_shared(std::string const &path);

   private:
    std::shared_ptr<impl> _impl;

    explicit database(std::string const &path);

    database(database const &) = delete;
    database(database &&) = delete;
    database &operator=(database const &) = delete;
    database &operator=(database &&) = delete;

    void _prepare(database_ptr const &);

    void row_set_did_close(uintptr_t const) override;
};
}  // namespace yas::db
