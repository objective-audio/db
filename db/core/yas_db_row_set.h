//
//  yas_db_row_set.h
//

#pragma once

#include <db/yas_db_protocol.h>
#include <db/yas_db_ptr.h>
#include <db/yas_db_result_code.h>
#include <db/yas_db_types.h>
#include <db/yas_db_value.h>

#include <string>

namespace yas {
template <typename T, typename U>
class result;
}

namespace yas::db {
class statement;
class value;

struct next_result_code final : result_code {
    next_result_code(int const &value);

    explicit operator bool() const;
};

struct row_set final : closable, db_settable {
    using index_result_t = result<int, std::nullptr_t>;

    ~row_set();

    [[nodiscard]] uintptr_t identifier() const;

    [[nodiscard]] db::statement_ptr const &statement() const;

    [[nodiscard]] db::next_result_code next();
    [[nodiscard]] bool has_row();

    [[nodiscard]] int column_count() const;
    [[nodiscard]] index_result_t column_index(std::string column_name) const;
    [[nodiscard]] std::string column_name(int const column_idx) const;
    [[nodiscard]] bool column_is_null(int const column_idx);
    [[nodiscard]] bool column_is_null(std::string column_name);

    [[nodiscard]] db::value column_value(int const column_idx) const;
    [[nodiscard]] db::value column_value(std::string column_name) const;

    [[nodiscard]] db::value_map_t values() const;

    [[nodiscard]] static row_set_ptr make_shared(db::statement_ptr const &, database_ptr const &,
                                                 std::vector<db::value> const &);

   private:
    db::database_ptr _database;
    db::statement_ptr const _statement;
    std::vector<db::value> _context;
    mutable std::unordered_map<std::string, int> _column_name_to_index_map;

    row_set(db::statement_ptr const &, database_ptr const &, std::vector<db::value> const &);

    void close() override;
    void set_database(database_ptr const &) override;

    std::unordered_map<std::string, int> const &_get_or_make_column_name_to_index_map() const;
};
}  // namespace yas::db
