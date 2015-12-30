//
//  yas_db_value.cpp
//

#include "yas_db_value.h"

using namespace yas;

#pragma mark - value::data

db::blob::blob() : _vector(), _data(nullptr), _size(0) {
}

template <>
db::blob::blob(const void *const data, std::size_t const size, copy_tag_t const)
    : _vector(size), _data(data), _size(size) {
    memcpy(_vector.data(), data, size);
}

template <>
db::blob::blob(const void *const data, std::size_t const size, no_copy_tag_t const)
    : _vector(), _data(data), _size(size) {
}

const void *db::blob::data() const {
    return _data;
}

std::size_t db::blob::size() const {
    return _size;
}

#pragma mark - value::impl

struct db::value::impl_base : public base::impl {
    virtual std::type_info const &type() const = 0;
};

template <typename T>
struct db::value::impl : public impl_base {
    typename T::type value;

    impl(typename T::type const &val) : value(val) {
    }

    impl(typename T::type &&val) : value(std::move(val)) {
    }

    std::type_info const &type() const override {
        return typeid(T);
    }
};

#pragma mark - value

db::value::value(UInt8 const &value) : super_class(std::make_unique<impl<db::integer>>(value)) {
}
db::value::value(SInt8 const &value) : super_class(std::make_unique<impl<db::integer>>(value)) {
}
db::value::value(UInt16 const &value) : super_class(std::make_unique<impl<db::integer>>(value)) {
}
db::value::value(SInt16 const &value) : super_class(std::make_unique<impl<db::integer>>(value)) {
}
db::value::value(UInt32 const &value) : super_class(std::make_unique<impl<db::integer>>(value)) {
}
db::value::value(SInt32 const &value) : super_class(std::make_unique<impl<db::integer>>(value)) {
}
db::value::value(UInt64 const &value) : super_class(std::make_unique<impl<db::integer>>(value)) {
}
db::value::value(SInt64 const &value) : super_class(std::make_unique<impl<db::integer>>(value)) {
}

db::value::value(Float32 const &value) : super_class(std::make_unique<impl<real>>(value)) {
}
db::value::value(Float64 const &value) : super_class(std::make_unique<impl<real>>(value)) {
}

db::value::value(std::string const &value) : super_class(std::make_unique<impl<text>>(value)) {
}
db::value::value(std::string &&value) : super_class(std::make_unique<impl<text>>(std::move(value))) {
}

db::value::value(blob::type &&value) : super_class(std::make_unique<impl<blob>>(std::move(value))) {
}

db::value::value(null::type) : super_class(std::make_unique<impl<null>>(nullptr)) {
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

std::type_info const &db::value::type() const {
    return impl_ptr<impl_base>()->type();
}

template <typename T>
typename T::type const &db::value::get() const {
    if (auto ip = std::dynamic_pointer_cast<impl<T>>(impl_ptr())) {
        return ip->value;
    }

    static const typename T::type _default{};
    return _default;
}

template db::integer::type const &db::value::get<db::integer>() const;
template db::real::type const &db::value::get<db::real>() const;
template db::text::type const &db::value::get<db::text>() const;
template db::blob::type const &db::value::get<db::blob>() const;
template db::null::type const &db::value::get<db::null>() const;

#pragma mark -

std::string yas::to_string(const db::value &value) {
    auto const &type = value.type();
    std::string type_name;
    std::string value_text;

    if (type == typeid(db::integer)) {
        type_name = db::integer::name;
        value_text = std::to_string(value.get<db::integer>());
    } else if (type == typeid(db::real)) {
        type_name = db::real::name;
        value_text = std::to_string(value.get<db::real>());
    } else if (type == typeid(db::text)) {
        type_name = db::text::name;
        value_text = value.get<db::text>();
    } else if (type == typeid(db::blob)) {
        type_name = db::blob::name;
        value_text = "data' size='" + std::to_string(value.get<db::blob>().size());
    } else if (type == typeid(db::null)) {
        type_name = db::null::name;
        value_text = "null";
    } else {
        type_name = "unknown";
    }

    return "type='" + type_name + "' value='" + value_text + "'";
}
