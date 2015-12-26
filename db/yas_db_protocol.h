//
//  yas_db_protocol.h
//

#pragma once

namespace yas {
namespace db {
    class database;
    class result_set;

    struct closable {
        virtual ~closable() = default;

        virtual void _close() = 0;
    };

    struct result_set_observable {
        virtual ~result_set_observable() = default;

        virtual void _result_set_did_close(const uintptr_t) = 0;
    };

    struct db_holdable {
        virtual ~db_holdable() = default;

        virtual void _set_database(const database &) = 0;
    };
}
}
