//
//  yas_db_result_code.h
//

#pragma once

#include <ostream>
#include <string>

namespace yas::db {
struct result_code {
    explicit result_code(int const &);

    [[nodiscard]] int raw_value() const;

   private:
    int _raw_value;
};
}  // namespace yas::db

namespace yas {
[[nodiscard]] std::string to_string(db::result_code const &);
}

std::ostream &operator<<(std::ostream &, yas::db::result_code const &);
