//
//  yas_db_protocol.h
//

#pragma once

#include "yas_protocol.h"

namespace yas::db {
class database;

struct closable : protocol {
    struct impl : protocol::impl {
        virtual void close() = 0;
    };

    explicit closable(std::shared_ptr<impl> impl) : protocol(std::move(impl)) {
    }

    closable(std::nullptr_t) : protocol(nullptr) {
    }

    void close() {
        impl_ptr<impl>()->close();
    }
};

struct row_set_observable : protocol {
    struct impl : protocol::impl {
        virtual void _row_set_did_close(uintptr_t const) = 0;
    };

    explicit row_set_observable(std::shared_ptr<impl> impl) : protocol(std::move(impl)) {
    }

    row_set_observable(std::nullptr_t) : protocol(nullptr) {
    }

    void row_set_did_close(uintptr_t const identifier) {
        impl_ptr<impl>()->_row_set_did_close(identifier);
    }
};

struct db_settable : protocol {
    struct impl : protocol::impl {
        virtual void _set_database(database const &) = 0;
    };

    explicit db_settable(std::shared_ptr<impl> impl) : protocol(std::move(impl)) {
    }

    db_settable(std::nullptr_t) : protocol(nullptr) {
    }

    void set_database(database const &db) {
        impl_ptr<impl>()->_set_database(db);
    }
};
}  // namespace yas::db
