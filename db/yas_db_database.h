//
//  yas_db_database.h
//

#pragma once

#include <MacTypes.h>
#include <sqlite3.h>
#include <chrono>
#include <functional>
#include "yas_base.h"
#include "yas_db_column_value.h"
#include "yas_db_protocol.h"
#include "yas_db_result_code.h"
#include "yas_result.h"

namespace yas {
namespace db {
    union callback_id {
        void *v;
        struct {
            UInt8 database;
        };
    };

    struct sqlite_result_code : public result_code {
        sqlite_result_code(int const &code = SQLITE_OK);

        explicit operator bool() const;
    };

    enum class error_type {
        closed,
        in_use,
        invalid_query_count,
        invalid_argument,
        sqlite,
    };

    struct error {
        error(error_type const type, sqlite_result_code const &code = 0, std::string const &message = "")
            : _type(type), _code(code), _message(message) {
        }

        error_type const &type() const {
            return _type;
        }

        sqlite_result_code const &code() const {
            return _code;
        }

        std::string const &message() const {
            return _message;
        }

       private:
        error_type _type;
        sqlite_result_code _code;
        std::string _message;
    };

    using update_result = result<std::nullptr_t, error>;
    using query_result = result<result_set, error>;
    using row_result = result<sqlite3_int64, error>;
    using count_result = result<int, error>;

    class database : public base, public result_set_observable {
        using super_class = base;

       public:
        class impl;

        using callback_function = std::function<int(const column_map &)>;

        static std::string sqlite_lib_version();
        static bool sqlite_thread_safe();

        explicit database(std::string const &path);
        database(std::nullptr_t);

        ~database();

        std::string const &database_path() const;
        sqlite3 *sqlite_handle() const;

        bool open();
#if SQLITE_VERSION_NUMBER >= 3005000
        bool open(int flags);
#endif
        void close();
        bool good_connection();

        update_result execute_update(std::string const &sql);
        update_result execute_update(std::string const &sql, column_vector const &arguments);
        update_result execute_update(std::string const &sql, column_map const &arguments);

        update_result execute_statements(std::string const &sql);
        update_result execute_statements(std::string const &sql, const callback_function &callback);
        const callback_function &callback_for_execute_statements() const;

        query_result execute_query(std::string const &sql) const;
        query_result execute_query(std::string const &sql, column_vector const &arguments) const;
        query_result execute_query(std::string const &sql, column_map const &arguments) const;

        row_result last_insert_row_id() const;
        count_result changes() const;

        update_result begin_transaction();
        update_result begin_deferred_transaction();
        update_result commit();
        update_result rollback();
        bool in_transaction();

        void clear_cached_statements();
        void close_open_result_sets();
        bool has_open_result_sets() const;
        bool should_cache_statements() const;
        void set_should_cache_statements(bool flag);

        std::string last_error_message() const;
        int last_error_code() const;
        bool had_error() const;
        void set_max_busy_retry_time_interval(const double);
        double max_busy_retry_time_interval() const;
        void set_start_busy_retry_time(const std::chrono::time_point<std::chrono::system_clock> &time);
        std::chrono::time_point<std::chrono::system_clock> start_busy_retry_time() const;

#if SQLITE_VERSION_NUMBER >= 3007000
        update_result start_save_point(std::string const &name);
        update_result release_save_point(std::string const &name);
        update_result rollback_save_point(std::string const &name);

        update_result in_save_point(const std::function<void(bool &rollback)> function);
#endif
        bool table_exists(std::string const &table_name) const;
        db::result_set get_schema() const;
        db::result_set get_table_schema(std::string const &table_name) const;
        bool column_exists(std::string const &column_name, std::string const &table_name) const;

       private:
        void _result_set_did_close(const uintptr_t) override;
    };
}
}
