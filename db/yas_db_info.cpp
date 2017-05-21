//
//  yas_db_info.cpp
//

#include "yas_db_info.h"

using namespace yas;

struct db::info::impl : public base::impl {
    db::value _version;
    db::value _current_save_id;
    db::value _last_save_id;

    impl(std::string &&version, db::integer::type const current_save_id, db::integer::type const last_save_id)
        : _version(std::move(version)), _current_save_id(current_save_id), _last_save_id(last_save_id) {
    }
};

db::info::info(std::string version, db::integer::type const current_save_id, db::integer::type const last_save_id)
    : base(std::make_shared<impl>(std::move(version), current_save_id, last_save_id)) {
}

db::info::info(db::value_map_t values)
    : info(values.at(db::version_field).get<db::text>(), values.at(db::current_save_id_field).get<db::integer>(),
           values.at(db::last_save_id_field).get<db::integer>()) {
}

db::info::info(std::nullptr_t) : base(nullptr) {
}

std::string const &db::info::version() const {
    return impl_ptr<impl>()->_version.get<db::text>();
}

db::integer::type const &db::info::current_save_id() const {
    return impl_ptr<impl>()->_current_save_id.get<db::integer>();
}

db::integer::type const &db::info::last_save_id() const {
    return impl_ptr<impl>()->_last_save_id.get<db::integer>();
}

db::value const &db::info::version_value() const {
    return impl_ptr<impl>()->_version;
}

db::value const &db::info::current_save_id_value() const {
    return impl_ptr<impl>()->_current_save_id;
}

db::value const &db::info::last_save_id_value() const {
    return impl_ptr<impl>()->_last_save_id;
}

db::info const &db::info::null_info() {
    static db::info const _null_info{nullptr};
    return _null_info;
}
