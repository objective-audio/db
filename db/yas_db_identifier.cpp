//
//  yas_db_identifier.cpp
//

#include "yas_db_identifier.h"

using namespace yas;

struct db::identifier::impl : base::impl {
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

db::identifier::identifier(db::value value, bool const is_tmp)
    : base(std::make_shared<impl>(std::move(value), is_tmp)) {
}

db::identifier::identifier(std::nullptr_t) : base(nullptr) {
}

void db::identifier::set_stable(db::integer::type const value) {
    this->set_stable(db::value{value});
}

void db::identifier::set_stable(db::value value) {
    impl_ptr<impl>()->_stable_value = std::move(value);
}

db::value const &db::identifier::stable() const {
    return impl_ptr<impl>()->_stable_value;
}

db::value const &db::identifier::temporary() const {
    return impl_ptr<impl>()->_tmp_value;
}

bool db::identifier::is_stable() const {
    return !!impl_ptr<impl>()->_stable_value;
}

bool db::identifier::is_temporary() const {
    return impl_ptr<impl>()->is_tmp();
}

db::identifier db::make_stable_id(db::value value) {
    return db::identifier{std::move(value), false};
}

db::identifier db::make_temporary_id(db::value value) {
    return db::identifier{std::move(value), true};
}

db::identifier const &db::null_id() {
    static db::identifier _null_id{nullptr};
    return _null_id;
}
