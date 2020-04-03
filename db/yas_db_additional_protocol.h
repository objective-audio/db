//
//  yas_db_additional_protocol.h
//

#pragma once

#include <cpp_utils/yas_result.h>

#include "yas_db_additional_types.h"

namespace yas::db {
struct manageable_object {
    virtual void set_status(db::object_status const &) = 0;
    virtual void load_insertion_data() = 0;
    virtual void load_data(db::object_data const &obj_data, bool const force = false) = 0;
    virtual void load_save_id(db::value const &save_id) = 0;
    virtual void clear_data() = 0;

    static manageable_object_ptr cast(manageable_object_ptr const &object) {
        return object;
    }
};
}  // namespace yas::db
