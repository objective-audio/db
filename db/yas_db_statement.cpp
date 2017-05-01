//
//  yas_db_statement.cpp
//

#include "yas_db_statement.h"

using namespace yas;

#pragma mark - statement::impl

class db::statement::impl : public base::impl, public closable::impl {
   public:
    ~impl() {
        this->close();
    }

    void close() override {
        if (this->_stmt) {
            sqlite3_finalize(this->_stmt);
            this->_stmt = nullptr;
        }

        this->_in_use = false;
    }

    void reset() {
        if (this->_stmt) {
            sqlite3_reset(this->_stmt);
        }

        this->_in_use = false;
    }

    sqlite3_stmt *_stmt;
    std::string _query;
    bool _in_use = false;
};

#pragma mark - statement

db::statement::statement() : base(std::make_unique<impl>()) {
}

db::statement::statement(std::nullptr_t) : base(nullptr) {
}

db::statement::~statement() = default;

void db::statement::set_stmt(sqlite3_stmt *const stmt) {
    impl_ptr<impl>()->_stmt = stmt;
}

sqlite3_stmt *db::statement::stmt() const {
    return impl_ptr<impl>()->_stmt;
}

void db::statement::set_query(std::string query) {
    impl_ptr<impl>()->_query = std::move(query);
}

std::string const &db::statement::query() const {
    return impl_ptr<impl>()->_query;
}

void db::statement::set_in_use(bool const in_use) {
    impl_ptr<impl>()->_in_use = in_use;
}

bool db::statement::in_use() const {
    return impl_ptr<impl>()->_in_use;
}

void db::statement::reset() {
    impl_ptr<impl>()->reset();
}

db::closable &db::statement::closable() {
    if (!this->_closable) {
        this->_closable = db::closable{impl_ptr<db::closable::impl>()};
    }
    return this->_closable;
}
