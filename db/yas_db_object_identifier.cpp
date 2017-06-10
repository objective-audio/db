//
//  yas_db_identifier.cpp
//

#include "yas_db_object_identifier.h"
#include "yas_stl_utils.h"

using namespace yas;

namespace yas {
namespace db {
    static void validate_tmp_value(db::value const &value) {
        if (value && value.type() != typeid(db::text)) {
            throw std::runtime_error("temporary value is not db::text type.");
        }
    }

    static void validate_stable_value(db::value const &value) {
        if (value && value.type() != typeid(db::integer)) {
            throw std::runtime_error("stable value is not db::integer type");
        }
    }
}
}

struct db::object_identifier::impl : base::impl {
    impl(db::value &&value, bool const is_tmp)
        : _stable_value(is_tmp ? db::null_value() : std::move(value)),
          _tmp_value(is_tmp ? std::move(value) : db::null_value()) {
        if (is_tmp) {
            if (_tmp_value) {
                db::validate_tmp_value(_tmp_value);
            } else {
                _tmp_value = db::value{std::to_string(this->identifier())};
            }
        } else {
            db::validate_stable_value(_stable_value);
        }
    }

    void set_stable(db::value &&value) {
        _stable_value = std::move(value);
        db::validate_stable_value(_stable_value);
    }

    db::value const &stable() {
        return _stable_value;
    }

    db::value const &temporary() {
        return _tmp_value;
    }

    bool is_stable() {
        return !!_stable_value;
    }

    bool is_tmp() {
        return !this->_stable_value && this->_tmp_value;
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

    std::size_t hash() {
        if (_tmp_value) {
            return std::hash<db::text::type>()(_tmp_value.get<db::text>());
        } else {
            return std::hash<db::integer::type>()(_stable_value.get<db::integer>());
        }
    }

   private:
    db::value _stable_value = db::null_value();
    db::value _tmp_value = db::null_value();
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
    impl_ptr<impl>()->set_stable(std::move(value));
}

db::value const &db::object_identifier::stable() const {
    return impl_ptr<impl>()->stable();
}

db::value const &db::object_identifier::temporary() const {
    return impl_ptr<impl>()->temporary();
}

bool db::object_identifier::is_stable() const {
    return !!impl_ptr<impl>()->is_stable();
}

bool db::object_identifier::is_temporary() const {
    return impl_ptr<impl>()->is_tmp();
}

db::object_identifier db::object_identifier::copy() const {
    if (this->is_temporary()) {
        return db::object_identifier{this->temporary(), true};
    } else {
        return db::make_stable_id(this->stable());
    }
}

std::size_t db::object_identifier::hash() const {
    return impl_ptr<impl>()->hash();
}

db::object_identifier db::make_stable_id(db::value value) {
    return db::object_identifier{std::move(value), false};
}

db::object_identifier db::make_temporary_id() {
    return db::object_identifier{db::value{nullptr}, true};
}

std::string yas::to_string(db::object_identifier const &obj_id) {
    return "[" + joined({"temporary:" + to_string(obj_id.temporary()), "stable:" + to_string(obj_id.stable())}, ", ") +
           "]";
}

db::object_identifier const &db::null_id() {
    static db::object_identifier _null_id{nullptr};
    return _null_id;
}
