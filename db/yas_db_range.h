//
//  yas_db_range.h
//

#pragma once

#include <MacTypes.h>
#include <string>

namespace yas {
namespace db {
    struct range {
        UInt64 const location;
        UInt64 const length;

        range(UInt64 const location, UInt64 const length);

        std::string sql() const;
    };
}
}
