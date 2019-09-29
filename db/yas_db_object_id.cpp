//
//  yas_db_object_id.cpp
//

#include "yas_db_object_id.h"
#include <cpp_utils/yas_stl_utils.h>

using namespace yas;

namespace yas::db {
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
}  // namespace yas::db

struct db::object_id::impl : weakable_impl {
    impl(db::value &&stable, db::value &&temporary) : _stable(std::move(stable)), _temporary(std::move(temporary)) {
        if (!_stable && !_temporary) {
            _temporary = db::value{std::to_string(this->identifier())};
        }
        db::validate_temporary(_temporary);
        db::validate_stable(_stable);
    }

    uintptr_t identifier() {
        return reinterpret_cast<uintptr_t>(this);
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

    bool is_equal(std::shared_ptr<impl> const &rhs) const {
        if (this->_temporary && rhs->_temporary) {
            return this->_temporary == rhs->_temporary;
        } else if (this->_stable && rhs->_stable) {
            return this->_stable == rhs->_stable;
        }

        return false;
    }

    std::size_t hash() {
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

db::object_id::object_id(db::value stable, db::value temporary)
    : _impl(std::make_shared<impl>(std::move(stable), std::move(temporary))) {
}

db::object_id::object_id(std::shared_ptr<weakable_impl> &&wimpl) : _impl(std::dynamic_pointer_cast<impl>(wimpl)) {
    assert(this->_impl);
}

db::object_id::object_id(std::nullptr_t) : _impl(nullptr) {
}

uintptr_t db::object_id::identifier() const {
    return this->_impl->identifier();
}

void db::object_id::set_stable(db::integer::type const value) {
    this->set_stable(db::value{value});
}

void db::object_id::set_stable(db::value value) {
    this->_impl->set_stable(std::move(value));
}

db::value const &db::object_id::stable_value() const {
    return this->_impl->stable();
}

db::value const &db::object_id::temporary_value() const {
    return this->_impl->temporary();
}

db::integer::type const &db::object_id::stable() const {
    return this->stable_value().get<db::integer>();
}

std::string const &db::object_id::temporary() const {
    return this->temporary_value().get<db::text>();
}

bool db::object_id::is_stable() const {
    return this->_impl->is_stable();
}

bool db::object_id::is_temporary() const {
    return this->_impl->is_tmp();
}

db::object_id db::object_id::copy() const {
    return db::object_id{this->stable_value(), this->_impl->temporary()};
}

std::size_t db::object_id::hash() const {
    return this->_impl->hash();
}

std::shared_ptr<weakable_impl> db::object_id::weakable_impl_ptr() const {
    return this->_impl;
}

bool db::object_id::operator==(object_id const &rhs) const {
    return this->_impl && rhs._impl && this->_impl->is_equal(rhs._impl);
}

bool db::object_id::operator!=(object_id const &rhs) const {
    return !(*this == rhs);
}

db::object_id::operator bool() const {
    return this->_impl != nullptr;
}

db::object_id db::make_stable_id(db::value stable) {
    return db::object_id{std::move(stable), db::null_value()};
}

db::object_id db::make_stable_id(db::integer::type const stable) {
    return db::object_id{db::value{stable}, db::null_value()};
}

db::object_id db::make_temporary_id() {
    return db::object_id{db::null_value(), db::null_value()};
}

std::string yas::to_string(db::object_id const &obj_id) {
    if (!obj_id) {
        return "null";
    }

    return "{" +
           joined({"stable:" + to_string(obj_id.stable_value()), "temporary:" + to_string(obj_id.temporary_value())},
                  ", ") +
           "}";
}

db::object_id const &db::null_id() {
    static db::object_id _null_id{nullptr};
    return _null_id;
}

db::object_id db::object_id_pool::get_or_create(std::string const &entity_name, object_id const &key,
                                                value_create_handler handler) {
    if (this->_all_values.count(entity_name) == 0) {
        this->_all_values.emplace(entity_name, value_map_t{});
    }

    auto &entity_values = this->_all_values.at(entity_name);

    if (entity_values.count(key) > 0) {
        if (auto const &value = entity_values.at(key)) {
            return value;
        } else {
            entity_values.erase(key);
        }
    }

    object_id value = handler();
    entity_values.emplace(key, value);
    return value;
}
