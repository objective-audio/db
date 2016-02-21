//
//  yas_db_value.h
//

#pragma once

#include <MacTypes.h>
#include <sqlite3.h>
#include <chrono>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>
#include "yas_base.h"

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
        using type = Float64;
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
        std::vector<UInt8> _vector;
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
        using super_class = base;

       public:
        explicit value(UInt8 const &);
        explicit value(SInt8 const &);
        explicit value(UInt16 const &);
        explicit value(SInt16 const &);
        explicit value(UInt32 const &);
        explicit value(SInt32 const &);
        explicit value(UInt64 const &);
        explicit value(SInt64 const &);
        explicit value(Float32 const &);
        explicit value(Float64 const &);
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

        bool operator==(value const &) const;
        bool operator!=(value const &) const;

        explicit operator bool() const;

        std::type_info const &type() const;

        template <typename T>
        typename T::type const &get() const;

        std::string sql() const;

        static value const &null_value();

       private:
        class impl_base;

        template <typename T>
        class impl;

        static std::shared_ptr<db::value::impl<null>> const &null_value_impl_ptr();
    };

    using value_vector = std::vector<value>;
    using value_map = std::unordered_map<std::string, value>;
    using value_vector_map = std::unordered_map<std::string, value_vector>;
    using value_map_vector = std::vector<db::value_map>;
    using value_map_vector_map = std::unordered_map<std::string, value_map_vector>;
    using time_point = std::chrono::time_point<std::chrono::system_clock, std::chrono::nanoseconds>;
}

std::string to_string(db::value const &);

db::time_point to_time_point(db::value const &);
db::value to_value(db::time_point const &);
}
