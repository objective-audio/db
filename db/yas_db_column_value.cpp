//
//  yas_db_column_value.cpp
//

#include "yas_db_column_value.h"

using namespace yas;

#pragma mark - column_value::data

db::blob::blob() : _vector(), _data(nullptr), _size(0) {
}

template <>
db::blob::blob(const void *const data, size_t const size, copy_tag_t const) : _vector(size), _data(data), _size(size) {
    memcpy(_vector.data(), data, size);
}

template <>
db::blob::blob(const void *const data, size_t const size, no_copy_tag_t const) : _vector(), _data(data), _size(size) {
}

const void *db::blob::data() const {
    return _data;
}

size_t db::blob::size() const {
    return _size;
}

#pragma mark - column_value::impl

struct db::column_value::impl_base {
    virtual ~impl_base() = default;
    virtual value_type type() const = 0;
};

template <typename T>
struct db::column_value::impl : public impl_base {
    typename T::type value;

    impl(typename T::type const &val) : value(val) {
    }

    impl(typename T::type &&val) : value(std::move(val)) {
    }

    value_type type() const override {
        return T::value_type;
    }
};

#pragma mark - column_value

db::column_value::column_value(int64::type const &value) : _impl(std::make_unique<impl<db::int64>>(value)) {
}

db::column_value::column_value(float64::type const &value) : _impl(std::make_unique<impl<float64>>(value)) {
}

db::column_value::column_value(string::type const &value) : _impl(std::make_unique<impl<string>>(value)) {
}

db::column_value::column_value(blob::type &&value) : _impl(std::make_unique<impl<blob>>(std::move(value))) {
}

db::column_value::column_value(null::type) : _impl(std::make_unique<impl<null>>(nullptr)) {
}

template <>
db::column_value::column_value(const void *const data_ptr, size_t const size, db::copy_tag_t const)
    : column_value(blob{data_ptr, size, db::copy_tag}) {
}

template <>
db::column_value::column_value(const void *const data_ptr, size_t const size, db::no_copy_tag_t const)
    : column_value(blob{data_ptr, size, db::no_copy_tag}) {
}

db::column_value::~column_value() = default;

db::column_value::column_value(column_value &&rhs) noexcept : _impl(std::move_if_noexcept(rhs._impl)) {
}

db::column_value &db::column_value::operator=(column_value &&rhs) noexcept {
    _impl = std::move_if_noexcept(rhs._impl);
    return *this;
}

db::value_type db::column_value::type() const {
    return _impl->type();
}

template <typename T>
const typename T::type &db::column_value::value() const {
    if (auto impl_ptr = dynamic_cast<impl<T> *>(_impl.get())) {
        return impl_ptr->value;
    }

    static const typename T::type _default{};
    return _default;
}

template db::int64::type const &db::column_value::value<db::int64>() const;
template db::float64::type const &db::column_value::value<db::float64>() const;
template db::string::type const &db::column_value::value<db::string>() const;
template db::blob::type const &db::column_value::value<db::blob>() const;
template db::null::type const &db::column_value::value<db::null>() const;

#pragma mark -

std::string yas::to_string(const db::value_type &value_type) {
    switch (value_type) {
        case db::value_type::int64:
            return "int64";
        case db::value_type::float64:
            return "float64";
        case db::value_type::string:
            return "string";
        case db::value_type::blob:
            return "blob";
        case db::value_type::null:
            return "null";
    }
}

std::string yas::to_string(const db::column_value &column_value) {
    std::string result = "type='" + to_string(column_value.type()) + "' value='";
    switch (column_value.type()) {
        case db::value_type::int64:
            result += std::to_string(column_value.value<db::int64>());
            break;
        case db::value_type::float64:
            result += std::to_string(column_value.value<db::float64>());
            break;
        case db::value_type::string:
            result += column_value.value<db::string>();
            break;
        case db::value_type::blob:
            result += "data' size='";
            result += std::to_string(column_value.value<db::blob>().size());
            break;
        case db::value_type::null:
            result += "null";
            break;
    }
    result += "'";
    return result;
}
