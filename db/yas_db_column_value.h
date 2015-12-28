//
//  yas_db_column_value.h
//

#pragma once

#include <MacTypes.h>
#include <sqlite3.h>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

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
        blob(const void *const data, size_t const size, T const tag = copy_tag);

        blob(const blob &) = delete;
        blob(blob &&) = default;
        blob &operator=(const blob &) = delete;
        blob &operator=(blob &&) = default;

        const void *data() const;
        size_t size() const;

       private:
        std::vector<UInt8> _vector;
        const void *_data;
        size_t _size;
    };

    struct null {
        using type = std::nullptr_t;
        static constexpr auto name = "null";
    };

    class column_value {
       public:
        explicit column_value(UInt8 const &);
        explicit column_value(SInt8 const &);
        explicit column_value(UInt16 const &);
        explicit column_value(SInt16 const &);
        explicit column_value(UInt32 const &);
        explicit column_value(SInt32 const &);
        explicit column_value(UInt64 const &);
        explicit column_value(SInt64 const &);
        explicit column_value(Float32 const &);
        explicit column_value(Float64 const &);
        explicit column_value(std::string const &);
        explicit column_value(std::string &&);
        explicit column_value(blob::type &&);
        column_value(null::type);

        template <typename T = db::copy_tag_t>
        column_value(const void *const data, size_t const size, T const tag = db::copy_tag);

        ~column_value();

        column_value(const column_value &) = delete;
        column_value(column_value &&) noexcept;
        column_value &operator=(const column_value &) = delete;
        column_value &operator=(column_value &&) noexcept;

        std::type_info const &type() const;

        template <typename T>
        const typename T::type &value() const;

       private:
        class impl_base;
        std::unique_ptr<impl_base> _impl;

        template <typename T>
        class impl;
    };

    using column_vector = std::vector<column_value>;
    using column_map = std::unordered_map<std::string, column_value>;

    static_assert(std::is_nothrow_move_constructible<column_value>::value == true,
                  "column_value is nothrow move constructible");
}

std::string to_string(const db::column_value &);
}
