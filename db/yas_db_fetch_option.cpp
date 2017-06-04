//
//  yas_db_fetch_option.cpp
//

#include "yas_db_fetch_option.h"

using namespace yas;

db::fetch_option::fetch_option() {
}

db::fetch_option::fetch_option(std::size_t const reserve) {
    _sel_options.reserve(reserve);
}

db::fetch_option::fetch_option(db::select_option sel_option)
    : fetch_option(db::select_option_map_t{{sel_option.table, std::move(sel_option)}}) {
}

db::fetch_option::fetch_option(select_option_map_t sel_options) {
    _sel_options = std::move(sel_options);
}

void db::fetch_option::add_select_option(db::select_option option) {
    if (_sel_options.count(option.table) > 0) {
        throw std::invalid_argument("duplicate table.");
    }

    _sel_options.emplace(option.table, std::move(option));
}

db::select_option_map_t const &db::fetch_option::select_options() const {
    return _sel_options;
}
