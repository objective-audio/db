//
//  yas_db_additional_protocol.h
//

#pragma once

namespace yas {
namespace db {
    class object;
    class manager;

    enum class object_status {
        invalid,
        saved,
        changed,
        updating,
    };

    struct manageable {
        virtual ~manageable() = default;

        virtual void set_status(object_status const &) = 0;
    };

    struct object_observable {
        virtual ~object_observable() = default;

        virtual void _object_did_change(object const &) = 0;
        virtual void _object_did_erase(std::string const &entity_name, integer::type const object_id) = 0;
    };
}
}
