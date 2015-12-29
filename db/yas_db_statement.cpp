//
//  yas_db_statement.cpp
//

#include "yas_db_statement.h"

using namespace yas;

#pragma mark - statement::impl

class db::statement::impl : public base::impl {
   public:
    impl() : stmt(), query(), in_use() {
    }

    ~impl() {
        close();
    }

    void close() {
        if (auto stmt_ptr = stmt.value()) {
            sqlite3_finalize(stmt_ptr);
            stmt.set_value(nullptr);
        }

        in_use.set_value(false);
    }

    void reset() {
        if (auto stmt_ptr = stmt.value()) {
            sqlite3_reset(stmt_ptr);
        }

        in_use.set_value(false);
    }

    property<sqlite3_stmt *> stmt;
    property<std::string> query;
    property<bool> in_use;
};

#pragma mark - statement

db::statement::statement() : super_class(std::make_unique<impl>()) {
}

db::statement::statement(std::nullptr_t) : super_class(nullptr) {
}

db::statement::~statement() = default;

void db::statement::_close() {
    impl_ptr<impl>()->close();
}

property<sqlite3_stmt *> &db::statement::stmt() {
    return impl_ptr<impl>()->stmt;
}

property<sqlite3_stmt *> const &db::statement::stmt() const {
    return impl_ptr<impl>()->stmt;
}

property<std::string> &db::statement::query() {
    return impl_ptr<impl>()->query;
}

property<std::string> const &db::statement::query() const {
    return impl_ptr<impl>()->query;
}

property<bool> &db::statement::in_use() {
    return impl_ptr<impl>()->in_use;
}

property<bool> const &db::statement::in_use() const {
    return impl_ptr<impl>()->in_use;
}

void db::statement::reset() {
    impl_ptr<impl>()->reset();
}
