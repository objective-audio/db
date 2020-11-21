//
//  yas_db_protocol.h
//

#pragma once

#include <db/yas_db_ptr.h>

namespace yas::db {
class database;

struct closable {
    virtual ~closable() = default;

    virtual void close() = 0;

    static closable_ptr cast(closable_ptr const &closable) {
        return closable;
    }
};

struct row_set_observable {
    virtual ~row_set_observable() = default;

    virtual void row_set_did_close(uintptr_t const) = 0;

    static row_set_observable_ptr cast(row_set_observable_ptr const &observable) {
        return observable;
    }
};

struct db_settable {
    virtual ~db_settable() = default;

    virtual void set_database(database_ptr const &) = 0;

    static db_settable_ptr cast(db_settable_ptr const &settable) {
        return settable;
    }
};
}  // namespace yas::db
