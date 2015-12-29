//
//  yas_db_result_code.h
//

#pragma once

#include <string>

namespace yas {
namespace db {
    class result_code {
       public:
        explicit result_code(int const &);
        ~result_code();

        int raw_value() const;

       private:
        int _raw_value;
    };
}

std::string to_string(db::result_code const &);
}