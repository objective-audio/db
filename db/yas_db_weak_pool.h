//
//  yas_db_pool.h
//

#pragma once

#include <cpp_utils/yas_weakable.h>
#include <functional>
#include <unordered_map>

namespace yas::db {
template <typename K, typename V>
struct weak_pool {
    using value_map_t = std::unordered_map<K, weak_ref<V>>;
    using value_create_handler = std::function<V(void)>;
    using perform_handler = std::function<void(std::string const &, K const &, V &)>;

    V get_or_create(std::string const &entity_name, K const &key, value_create_handler handler);
    V get(std::string const &entity_name, K const &key);
    void set(std::string const &entity_name, K const &key, V value);

    void perform(perform_handler const &handler);
    void perform_entity(std::string const &entity_name, perform_handler const &handler);
    void erase(std::string const &entity_name, K const &key);
    void clear();

   private:
    std::unordered_map<std::string, value_map_t> _all_values;
};
}  // namespace yas::db

#include "yas_db_weak_pool_private.h"
