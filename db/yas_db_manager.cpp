//
//  yas_db_manager.cpp
//

#include "yas_db_manager.h"

using namespace yas;

struct db::manager::impl : public base::impl {
    impl(std::string const &path) {
    }
};

db::manager::manager(std::string const &path) : super_class(std::make_shared<impl>(path)) {
}

db::manager::manager(std::nullptr_t) : super_class(nullptr) {
}