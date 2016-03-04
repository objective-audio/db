//
//  yas_db_additional_protocol.h
//

#pragma once

#include "yas_db_value.h"

namespace yas {
namespace db {
    class object;

    static std::string const info_table = "db_info";
    static std::string const version_field = "version";
    static std::string const current_save_id_field = "cur_save_id";
    static std::string const last_save_id_field = "last_save_id";

    enum class object_status {
        invalid,
        inserted,
        saved,
        changed,
        updating,
    };

    struct manageable {
        virtual ~manageable() = default;

        virtual void set_status(object_status const &) = 0;
        virtual void load_insertion_data() = 0;
    };

    struct object_observable {
        virtual ~object_observable() = default;

        virtual void _object_did_change(object const &) = 0;
        virtual void _object_did_erase(std::string const &entity_name, integer::type const object_id) = 0;
    };
}
}
