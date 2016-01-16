//
//  yas_db_additional_protocol.h
//

#pragma once

namespace yas {
namespace db {
    enum class object_status {
        invalid,
        saved,
        changed,
        updating,
    };

    struct object_manageable {
        virtual ~object_manageable() = default;

        virtual void set_status(object_status const &) = 0;
    };
}
}
