//
//  yas_db_identifier.cpp
//

#include "yas_db_object_identifier.h"

using namespace yas;

struct db::object_identifier::impl : base::impl {
    db::value _stable_value = db::null_value();
    db::value _tmp_value = db::null_value();

    impl(db::value &&value, bool const is_tmp)
        : _stable_value(is_tmp ? db::null_value() : std::move(value)),
          _tmp_value(is_tmp ? std::move(value) : db::null_value()) {
    }

    virtual bool is_equal(std::shared_ptr<base::impl> const &rhs) const override {
        if (auto casted_rhs = std::dynamic_pointer_cast<impl>(rhs)) {
            if (this->_tmp_value && casted_rhs->_tmp_value) {
                return this->_tmp_value == casted_rhs->_tmp_value;
            } else if (this->_stable_value && casted_rhs->_stable_value) {
                return this->_stable_value == casted_rhs->_stable_value;
            }
        }

        return false;
    }

    bool is_tmp() {
        return !this->_stable_value && this->_tmp_value;
    }
};

db::object_identifier::object_identifier(db::value value, bool const is_tmp)
    : base(std::make_shared<impl>(std::move(value), is_tmp)) {
}

db::object_identifier::object_identifier(std::nullptr_t) : base(nullptr) {
}

void db::object_identifier::set_stable(db::integer::type const value) {
    this->set_stable(db::value{value});
}

void db::object_identifier::set_stable(db::value value) {
    impl_ptr<impl>()->_stable_value = std::move(value);
}

db::value const &db::object_identifier::stable() const {
    return impl_ptr<impl>()->_stable_value;
}

db::value const &db::object_identifier::temporary() const {
    return impl_ptr<impl>()->_tmp_value;
}

bool db::object_identifier::is_stable() const {
    return !!impl_ptr<impl>()->_stable_value;
}

bool db::object_identifier::is_temporary() const {
    return impl_ptr<impl>()->is_tmp();
}

db::object_identifier db::object_identifier::copy() const {
    if (this->is_temporary()) {
        return db::make_temporary_id(this->temporary());
    } else {
        return db::make_stable_id(this->stable());
    }
}

db::object_identifier db::make_stable_id(db::value value) {
    return db::object_identifier{std::move(value), false};
}

db::object_identifier db::make_temporary_id(db::value value) {
    return db::object_identifier{std::move(value), true};
}

db::object_identifier const &db::null_id() {
    static db::object_identifier _null_id{nullptr};
    return _null_id;
}
