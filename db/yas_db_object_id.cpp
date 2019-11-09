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

struct db::object_id::impl {
    impl(db::value &&stable, db::value &&temporary) : _stable(std::move(stable)), _temporary(std::move(temporary)) {
    }

    uintptr_t identifier() {
        return reinterpret_cast<uintptr_t>(this);
    }

    db::value _stable;
    db::value _temporary;
};

db::object_id::object_id(db::value stable, db::value temporary)
    : _impl(std::make_shared<impl>(std::move(stable), std::move(temporary))) {
    if (!this->stable_value() && !this->temporary_value()) {
        this->_impl->_temporary = db::value{std::to_string(this->identifier())};
    }
    db::validate_temporary(this->temporary_value());
    db::validate_stable(this->stable_value());
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
    this->_impl->_stable = std::move(value);
    db::validate_stable(this->stable_value());
}

db::value const &db::object_id::stable_value() const {
    return this->_impl->_stable;
}

db::value const &db::object_id::temporary_value() const {
    return this->_impl->_temporary;
}

db::integer::type const &db::object_id::stable() const {
    return this->stable_value().get<db::integer>();
}

std::string const &db::object_id::temporary() const {
    return this->temporary_value().get<db::text>();
}

bool db::object_id::is_stable() const {
    return !!this->stable_value();
}

bool db::object_id::is_temporary() const {
    return !this->stable_value() && this->temporary_value();
}

db::object_id db::object_id::copy() const {
    return db::object_id{this->stable_value(), this->temporary_value()};
}

std::size_t db::object_id::hash() const {
    if (auto const &stable = this->stable_value()) {
        return std::hash<db::integer::type>()(stable.get<db::integer>());
    } else {
        return std::hash<db::text::type>()(this->temporary_value().get<db::text>());
    }
}

bool db::object_id::operator==(object_id const &rhs) const {
    return this->_impl && rhs._impl && this->_is_equal(rhs);
}

bool db::object_id::operator!=(object_id const &rhs) const {
    return !(*this == rhs);
}

db::object_id::operator bool() const {
    return this->_impl != nullptr;
}

bool db::object_id::_is_equal(object_id const &rhs) const {
    auto const &lhs_temporary = this->temporary_value();
    auto const &rhs_temporary = rhs.temporary_value();
    if (lhs_temporary && rhs_temporary) {
        return lhs_temporary == rhs_temporary;
    } else {
        auto const &lhs_stable = this->stable_value();
        auto const &rhs_stable = rhs.stable_value();
        if (lhs_stable && rhs_stable) {
            return lhs_stable == rhs_stable;
        }
    }

    return false;
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
