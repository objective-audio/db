//
//  yas_db_fetch_option.h
//

#pragma once

#include "yas_db_select_option.h"
#include <unordered_map>

namespace yas {
namespace db {
    using select_option_map_t = std::unordered_map<std::string, db::select_option>;

    struct fetch_option {
        fetch_option();
        explicit fetch_option(std::size_t const reserve);
        explicit fetch_option(db::select_option);
        explicit fetch_option(db::select_option_map_t);

        void add_select_option(db::select_option);
        select_option_map_t const &select_options() const;

       private:
        select_option_map_t _sel_options;
    };
}
}
