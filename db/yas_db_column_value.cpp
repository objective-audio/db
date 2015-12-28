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
    virtual std::type_info const &type() const = 0;
};

template <typename T>
struct db::column_value::impl : public impl_base {
    typename T::type value;

    impl(typename T::type const &val) : value(val) {
    }

    impl(typename T::type &&val) : value(std::move(val)) {
    }

    std::type_info const &type() const override {
        return typeid(T);
    }
};

#pragma mark - column_value

db::column_value::column_value(UInt8 const &value) : _impl(std::make_unique<impl<db::integer>>(value)) {
}
db::column_value::column_value(SInt8 const &value) : _impl(std::make_unique<impl<db::integer>>(value)) {
}
db::column_value::column_value(UInt16 const &value) : _impl(std::make_unique<impl<db::integer>>(value)) {
}
db::column_value::column_value(SInt16 const &value) : _impl(std::make_unique<impl<db::integer>>(value)) {
}
db::column_value::column_value(UInt32 const &value) : _impl(std::make_unique<impl<db::integer>>(value)) {
}
db::column_value::column_value(SInt32 const &value) : _impl(std::make_unique<impl<db::integer>>(value)) {
}
db::column_value::column_value(UInt64 const &value) : _impl(std::make_unique<impl<db::integer>>(value)) {
}
db::column_value::column_value(SInt64 const &value) : _impl(std::make_unique<impl<db::integer>>(value)) {
}

db::column_value::column_value(Float32 const &value) : _impl(std::make_unique<impl<real>>(value)) {
}
db::column_value::column_value(Float64 const &value) : _impl(std::make_unique<impl<real>>(value)) {
}

db::column_value::column_value(std::string const &value) : _impl(std::make_unique<impl<text>>(value)) {
}
db::column_value::column_value(std::string &&value) : _impl(std::make_unique<impl<text>>(std::move(value))) {
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

std::type_info const &db::column_value::type() const {
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

template db::integer::type const &db::column_value::value<db::integer>() const;
template db::real::type const &db::column_value::value<db::real>() const;
template db::text::type const &db::column_value::value<db::text>() const;
template db::blob::type const &db::column_value::value<db::blob>() const;
template db::null::type const &db::column_value::value<db::null>() const;

#pragma mark -

std::string yas::to_string(const db::column_value &column_value) {
    auto const &type = column_value.type();
    std::string type_name;
    std::string value_text;

    if (type == typeid(db::integer)) {
        type_name = db::integer::name;
        value_text = std::to_string(column_value.value<db::integer>());
    } else if (type == typeid(db::real)) {
        type_name = db::real::name;
        value_text = std::to_string(column_value.value<db::real>());
    } else if (type == typeid(db::text)) {
        type_name = db::text::name;
        value_text = column_value.value<db::text>();
    } else if (type == typeid(db::blob)) {
        type_name = db::blob::name;
        value_text = "data' size='" + std::to_string(column_value.value<db::blob>().size());
    } else if (type == typeid(db::null)) {
        type_name = db::null::name;
        value_text = "null";
    } else {
        type_name = "unknown";
    }

    return "type='" + type_name + "' value='" + value_text + "'";
}
