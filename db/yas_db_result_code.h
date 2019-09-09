//
//  yas_db_result_code.h
//

#pragma once

#include <string>

namespace yas::db {
struct result_code {
    explicit result_code(int const &);

    int raw_value() const;

   private:
    int _raw_value;
};
}  // namespace yas::db

namespace yas {
std::string to_string(db::result_code const &);
}
