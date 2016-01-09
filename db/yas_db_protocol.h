//
//  yas_db_protocol.h
//

#pragma once

namespace yas {
namespace db {
    class database;
    class row_set;

    struct closable {
        virtual ~closable() = default;

        virtual void _close() = 0;
    };

    struct row_set_observable {
        virtual ~row_set_observable() = default;

        virtual void _row_set_did_close(const uintptr_t) = 0;
    };

    struct db_holdable {
        virtual ~db_holdable() = default;

        virtual void _set_database(const database &) = 0;
    };
}
}
