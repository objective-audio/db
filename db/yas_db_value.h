//
//  yas_db_value.h
//

#pragma once

#include <memory>
#include <string>
#include <vector>
#include "yas_base.h"
#include "yas_db_types.h"
#include "yas_db_protocol.h"

namespace yas {
namespace db {
    struct copy_tag_t {};
    struct no_copy_tag_t {};
    constexpr static copy_tag_t copy_tag{};
    constexpr static no_copy_tag_t no_copy_tag{};

    struct integer {
        using type = sqlite3_int64;
        static constexpr auto name = "INTEGER";
    };

    struct real {
        using type = double;
        static constexpr auto name = "REAL";
    };

    struct text {
        using type = std::string;
        static constexpr auto name = "TEXT";
    };

    struct blob {
        using type = blob;
        static constexpr auto name = "BLOB";

        blob();

        template <typename T = copy_tag_t>
        blob(const void *const data, std::size_t const size, T const tag = copy_tag);

        blob(blob &&) = default;
        blob &operator=(blob &&) = default;

        bool operator==(blob const &) const;
        bool operator!=(blob const &) const;

        const void *data() const;
        std::size_t size() const;

       private:
        std::vector<uint8_t> _vector;
        const void *_data;
        std::size_t _size;

        blob(const blob &) = delete;
        blob &operator=(const blob &) = delete;
    };

    struct null {
        using type = std::nullptr_t;
        static constexpr auto name = "NULL";
    };

    class value : public base {
        template <typename T>
        class impl;

       public:
        class impl_base;

        explicit value(uint8_t const &);
        explicit value(int8_t const &);
        explicit value(uint16_t const &);
        explicit value(int16_t const &);
        explicit value(uint32_t const &);
        explicit value(int32_t const &);
        explicit value(uint64_t const &);
        explicit value(int64_t const &);
        explicit value(float const &);
        explicit value(double const &);
        explicit value(std::string const &);
        explicit value(std::string &&);
        explicit value(blob::type &&);
        value(null::type);

        template <typename T = db::copy_tag_t>
        value(const void *const data, std::size_t const size, T const tag = db::copy_tag);

        value(value const &);
        value(value &&);
        value &operator=(value const &);
        value &operator=(value &&);

        ~value();

        explicit operator bool() const;

        std::type_info const &type() const;

        template <typename T>
        typename T::type const &get() const;

        std::string sql() const;

       private:
        static std::shared_ptr<db::value::impl<null>> const &null_value_impl_ptr();
    };

    db::value const &null_value();
}

std::string to_string(db::value const &);
std::string to_string(db::value_map_t const &);
std::string to_string(db::value_map_vector_t const &, bool const formatted = false);
std::string to_string(db::value_map_vector_map_t const &, bool const formatted = false);

db::time_point_t to_time_point(db::value const &);
db::value to_value(db::time_point_t const &);
}

template <>
struct std::hash<yas::db::value> {
    std::size_t operator()(yas::db::value const &value) const {
        auto const &type = value.type();
        if (type == typeid(yas::db::integer)) {
            return std::hash<yas::db::integer::type>()(value.get<yas::db::integer>());
        } else if (type == typeid(yas::db::real)) {
            return std::hash<yas::db::real::type>()(value.get<yas::db::real>());
        } else if (type == typeid(yas::db::text)) {
            return std::hash<yas::db::text::type>()(value.get<yas::db::text>());
        }
        return 0;
    }
};
