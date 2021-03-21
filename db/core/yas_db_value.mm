//
//  yas_db_value.cpp
//

#include "yas_db_value.h"

#include <cpp_utils/yas_fast_each.h>
#include <cpp_utils/yas_stl_utils.h>

using namespace yas;
using namespace yas::db;

#pragma mark - value::data

blob::blob() : _vector(), _data(nullptr), _size(0) {
}

template <>
blob::blob(const void *const data, std::size_t const size, copy_tag_t const) : _vector(size), _data(data), _size(size) {
    memcpy(this->_vector.data(), data, size);
}

template <>
blob::blob(const void *const data, std::size_t const size, no_copy_tag_t const) : _vector(), _data(data), _size(size) {
}

bool blob::operator==(blob const &rhs) const {
    uint8_t const *lhs_data = static_cast<uint8_t const *>(data());
    uint8_t const *rhs_data = static_cast<uint8_t const *>(rhs.data());

    if (lhs_data == rhs_data) {
        return true;
    } else if (this->size() == rhs.size()) {
        auto each = make_fast_each(size());
        while (yas_each_next(each)) {
            std::size_t const &idx = yas_each_index(each);
            if (lhs_data[idx] != rhs_data[idx]) {
                return false;
            }
        }
        return true;
    }

    return false;
}

bool blob::operator!=(blob const &rhs) const {
    return !(*this == rhs);
}

const void *blob::data() const {
    return this->_data;
}

std::size_t blob::size() const {
    return this->_size;
}

#pragma mark - value::impl

struct db::value::impl {
    virtual std::type_info const &type() const = 0;
    virtual bool is_equal(std::shared_ptr<impl> const &rhs) const = 0;

    uintptr_t identifier() {
        return reinterpret_cast<uintptr_t>(this);
    }
};

template <typename T>
struct db::value::typed_impl : impl {
    typename T::type _value;

    typed_impl(typename T::type const &val) : _value(val) {
    }

    typed_impl(typename T::type &&val) : _value(std::move(val)) {
    }

    typed_impl(typed_impl const &) = delete;
    typed_impl(typed_impl &&) = delete;
    typed_impl &operator=(typed_impl const &) = delete;
    typed_impl &operator=(typed_impl &&) = delete;

    ~typed_impl() = default;

    virtual bool is_equal(std::shared_ptr<impl> const &rhs) const override {
        if (auto casted_rhs = std::dynamic_pointer_cast<typed_impl>(rhs)) {
            std::type_info const &type_info = type();
            if (type_info == casted_rhs->type()) {
                return this->_value == casted_rhs->_value;
            }
        }

        return false;
    }

    std::type_info const &type() const override {
        return typeid(T);
    }
};

#pragma mark - value

db::value::value(uint8_t const &value) : _impl(std::make_unique<typed_impl<db::integer>>(value)) {
}
db::value::value(int8_t const &value) : _impl(std::make_unique<typed_impl<db::integer>>(value)) {
}
db::value::value(uint16_t const &value) : _impl(std::make_unique<typed_impl<db::integer>>(value)) {
}
db::value::value(int16_t const &value) : _impl(std::make_unique<typed_impl<db::integer>>(value)) {
}
db::value::value(uint32_t const &value) : _impl(std::make_unique<typed_impl<db::integer>>(value)) {
}
db::value::value(int32_t const &value) : _impl(std::make_unique<typed_impl<db::integer>>(value)) {
}
db::value::value(uint64_t const &value) : _impl(std::make_unique<typed_impl<db::integer>>(value)) {
}
db::value::value(int64_t const &value) : _impl(std::make_unique<typed_impl<db::integer>>(value)) {
}

db::value::value(float const &value) : _impl(std::make_unique<typed_impl<real>>(value)) {
}
db::value::value(double const &value) : _impl(std::make_unique<typed_impl<real>>(value)) {
}

db::value::value(std::string const &value) : _impl(std::make_unique<typed_impl<text>>(value)) {
}
db::value::value(std::string &&value) : _impl(std::make_unique<typed_impl<text>>(std::move(value))) {
}

db::value::value(blob::type &&value) : _impl(std::make_unique<typed_impl<blob>>(std::move(value))) {
}

db::value::value(null::type) : _impl(null_value_impl_ptr()) {
}

template <>
db::value::value(const void *const data_ptr, std::size_t const size, db::copy_tag_t const)
    : value(blob{data_ptr, size, db::copy_tag}) {
}

template <>
db::value::value(const void *const data_ptr, std::size_t const size, db::no_copy_tag_t const)
    : value(blob{data_ptr, size, db::no_copy_tag}) {
}

db::value::~value() = default;

db::value::value(value const &) = default;

db::value::value(value &&rhs) : _impl(std::move(rhs._impl)) {
    rhs._impl = null_value_impl_ptr();
}

db::value &db::value::operator=(value const &) = default;

db::value &db::value::operator=(value &&rhs) {
    this->_impl = std::move(rhs._impl);
    rhs._impl = null_value_impl_ptr();
    return *this;
}

uintptr_t db::value::identifier() const {
    return this->_impl->identifier();
}

db::value::operator bool() const {
    return this->_impl != nullptr && this->type() != typeid(db::null);
}

std::type_info const &db::value::type() const {
    return this->_impl->type();
}

template <typename T>
typename T::type const &db::value::get() const {
    if (auto typed = std::dynamic_pointer_cast<typed_impl<T>>(this->_impl)) {
        return typed->_value;
    }

    static const typename T::type _default{};
    return _default;
}

template db::integer::type const &db::value::get<db::integer>() const;
template db::real::type const &db::value::get<db::real>() const;
template db::text::type const &db::value::get<db::text>() const;
template blob::type const &db::value::get<blob>() const;
template db::null::type const &db::value::get<db::null>() const;

std::string db::value::sql() const {
    std::type_info const &type_info = type();
    if (type_info == typeid(db::integer)) {
        return std::to_string(get<db::integer>());
    } else if (type_info == typeid(db::real)) {
        return std::to_string(get<db::real>());
    } else if (type_info == typeid(db::text)) {
        return "'" + get<db::text>() + "'";
    } else if (type_info == typeid(blob)) {
        throw std::runtime_error("don't get sql from blob value");
    } else {
        return "null";
    }

    return nullptr;
}

std::shared_ptr<db::value::typed_impl<db::null>> const &db::value::null_value_impl_ptr() {
    static auto _impl_ptr = std::make_shared<db::value::typed_impl<db::null>>(nullptr);
    return _impl_ptr;
}

bool db::value::operator==(value const &rhs) const {
    return this->_impl && rhs._impl && this->_impl->is_equal(rhs._impl);
}

bool db::value::operator!=(value const &rhs) const {
    return !(*this == rhs);
}

#pragma mark -

db::value const &db::null_value() {
    static db::value _null_value{nullptr};
    return _null_value;
}

std::string yas::to_string(const db::value &value) {
    std::type_info const &type = value.type();

    if (type == typeid(db::integer)) {
        return std::to_string(value.get<db::integer>());
    } else if (type == typeid(db::real)) {
        return std::to_string(value.get<db::real>());
    } else if (type == typeid(db::text)) {
        return "'" + value.get<db::text>() + "'";
    } else if (type == typeid(blob)) {
        //        return "data' size='" + std::to_string(value.get<blob>().size());
    } else if (type == typeid(db::null)) {
        return "null";
    }

    return std::string{};
}

std::string yas::to_string(db::value_vector_t const &vector) {
    auto components = to_vector<std::string>(vector, [](db::value const &value) { return to_string(value); });
    return "[" + joined(components, ",") + "]";
}

std::string yas::to_string(db::value_map_t const &map) {
    std::vector<std::string> components;
    for (auto const &pair : map) {
        components.emplace_back(pair.first + ":" + to_string(pair.second));
    }
    return "{" + joined(components, ",") + "}";
}

std::string yas::to_string(db::value_map_vector_t const &vector, bool const formatted) {
    std::string const new_line = formatted ? "\n" : "";

    std::vector<std::string> components;
    for (auto const &map : vector) {
        components.emplace_back(to_string(map));
    }
    return "[" + joined(components, "," + new_line) + "]";
}

std::string yas::to_string(db::value_map_vector_map_t const &map, bool const formatted) {
    std::vector<std::string> components;
    for (auto const &pair : map) {
        components.emplace_back(pair.first + ":" + to_string(pair.second, formatted));
    }
    return "{" + joined(components, ",") + "}";
}

db::time_point_t yas::to_time_point(db::value const &value) {
    if (value.type() == typeid(db::integer)) {
        db::integer::type integer_value = value.get<db::integer>();
        return db::time_point_t{std::chrono::nanoseconds{integer_value}};
    }
    return {};
}

db::value yas::to_value(db::time_point_t const &time_point) {
    return db::value{time_point.time_since_epoch().count()};
}

std::ostream &operator<<(std::ostream &os, db::value const &value) {
    os << to_string(value);
    return os;
}

std::ostream &operator<<(std::ostream &os, db::value_vector_t const &value) {
    os << to_string(value);
    return os;
}

std::ostream &operator<<(std::ostream &os, db::value_map_t const &value) {
    os << to_string(value);
    return os;
}

std::ostream &operator<<(std::ostream &os, db::value_map_vector_t const &value) {
    os << to_string(value, false);
    return os;
}

std::ostream &operator<<(std::ostream &os, db::value_map_vector_map_t const &value) {
    os << to_string(value, false);
    return os;
}
