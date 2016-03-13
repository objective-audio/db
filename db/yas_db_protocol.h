//
//  yas_db_protocol.h
//

#pragma once

#include "yas_protocol.h"

namespace yas {
namespace db {
    class database;

    struct closable : protocol {
        struct impl : protocol::impl {
            virtual void close() = 0;
        };

        explicit closable(std::shared_ptr<impl> impl) : protocol(std::move(impl)) {
        }

        void close() {
            impl_ptr<impl>()->close();
        }
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
