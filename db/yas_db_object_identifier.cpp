//
//  yas_db_identifier.cpp
//

#include "yas_db_object_identifier.h"
#include "yas_stl_utils.h"

using namespace yas;

namespace yas {
namespace db {
    static void validate_temporary(db::value const &value) {
        if (value && value.type() != typeid(db::text)) {
            throw std::runtime_error("temporary value is not db::text type.");
        }
    }

    static void validate_stable(db::value const &value) {
        if (value && value.type() != typeid(db::integer)) {
            throw std::runtime_error("stable value is not db::integer type");
        }
    }
}
}

struct db::object_identifier::impl : base::impl {
    impl(db::value &&stable, db::value &&temporary) : _stable(std::move(stable)), _temporary(std::move(temporary)) {
        if (!_stable && !_temporary) {
            _temporary = db::value{std::to_string(this->identifier())};
        }
        db::validate_temporary(_temporary);
        db::validate_stable(_stable);
    }

    void set_stable(db::value &&value) {
        _stable = std::move(value);
        db::validate_stable(_stable);
    }

    db::value const &stable() {
        return _stable;
    }

    db::value const &temporary() {
        return _temporary;
    }

    bool is_stable() {
        return !!_stable;
    }

    bool is_tmp() {
        return !this->_stable && this->_temporary;
    }

    virtual bool is_equal(std::shared_ptr<base::impl> const &rhs) const override {
        if (auto casted_rhs = std::dynamic_pointer_cast<impl>(rhs)) {
            if (this->_temporary && casted_rhs->_temporary) {
                return this->_temporary == casted_rhs->_temporary;
            } else if (this->_stable && casted_rhs->_stable) {
                return this->_stable == casted_rhs->_stable;
            }
        }

        return false;
    }

    std::size_t hash() {
#warning tempしかないものとstableのあるものは比べない。フェッチしてきたらまずキャッシュのidentifierにset_stableしてしまう
        if (_stable) {
            return std::hash<db::integer::type>()(_stable.get<db::integer>());
        } else {
            return std::hash<db::text::type>()(_temporary.get<db::text>());
        }
    }

   private:
    db::value _stable;
    db::value _temporary;
};

db::object_identifier::object_identifier(db::value stable, db::value temporary)
    : base(std::make_shared<impl>(std::move(stable), std::move(temporary))) {
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
    return db::object_identifier{this->stable(), this->temporary()};
}

std::size_t db::object_identifier::hash() const {
    return impl_ptr<impl>()->hash();
}

db::object_identifier db::make_stable_id(db::value stable) {
    return db::object_identifier{std::move(stable), db::null_value()};
}

db::object_identifier db::make_temporary_id() {
    return db::object_identifier{db::null_value(), db::null_value()};
}

std::string yas::to_string(db::object_identifier const &obj_id) {
    if (!obj_id) {
        return "null";
    }

    return "{" + joined({"temporary:" + to_string(obj_id.temporary()), "stable:" + to_string(obj_id.stable())}, ", ") +
           "}";
}

db::object_identifier const &db::null_id() {
    static db::object_identifier _null_id{nullptr};
    return _null_id;
}
