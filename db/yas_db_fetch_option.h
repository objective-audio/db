//
//  yas_db_fetch_option.h
//

#pragma once

#include <unordered_map>
#include "yas_db_select_option.h"

namespace yas::db {
using select_option_map_t = std::unordered_map<std::string, db::select_option>;

struct fetch_option {
    fetch_option();
    explicit fetch_option(std::size_t const reserve);

    void add_select_option(db::select_option);
    select_option_map_t const &select_options() const;

   private:
    select_option_map_t _sel_options;
};
}  // namespace yas::db
