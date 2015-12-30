//
//  yas_db_value.h
//

#pragma once

#include <MacTypes.h>
#include <sqlite3.h>
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
        static constexpr auto name = "integer";
    };

    struct real {
        using type = Float64;
        static constexpr auto name = "real";
    };

    struct text {
        using type = std::string;
        static constexpr auto name = "text";
    };

    struct blob {
        using type = blob;
        static constexpr auto name = "blob";

        blob();

        template <typename T = copy_tag_t>
        blob(const void *const data, std::size_t const size, T const tag = copy_tag);

        blob(blob &&) = default;
        blob &operator=(blob &&) = default;

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
        static constexpr auto name = "null";
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

        ~value();

        std::type_info const &type() const;

        template <typename T>
        typename T::type const &get() const;

       private:
        class impl_base;

        template <typename T>
        class impl;
    };

    using column_vector = std::vector<value>;
    using column_map = std::unordered_map<std::string, value>;
}

std::string to_string(const db::value &);
}
