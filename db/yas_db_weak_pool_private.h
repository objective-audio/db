//
//  yas_db_pool_private.h
//

#pragma once

namespace yas::db {
template <typename K, typename V>
V weak_pool<K, V>::get_or_create(std::string const &entity_name, K const &key, value_create_handler handler) {
    if (this->_all_values.count(entity_name) == 0) {
        this->_all_values.emplace(entity_name, value_map_t{});
    }

    auto &entity_values = this->_all_values.at(entity_name);

    if (entity_values.count(key) == 0) {
        V value = handler();
        entity_values.emplace(key, to_weak(value));
        return value;
    } else {
        return entity_values.at(key).lock();
    }
}

template <typename K, typename V>
V weak_pool<K, V>::get(std::string const &entity_name, K const &key) {
    if (this->_all_values.count(entity_name) > 0) {
        auto const &entity_values = this->_all_values.at(entity_name);
        if (entity_values.count(key) > 0) {
            return entity_values.at(key).lock();
        }
    }
    return V{nullptr};
}

template <typename K, typename V>
void weak_pool<K, V>::set(std::string const &entity_name, K const &key, V value) {
    if (this->_all_values.count(entity_name) == 0) {
        this->_all_values.emplace(entity_name, value_map_t{});
    }

    auto &entity_values = this->_all_values.at(entity_name);

    entity_values.emplace(key, std::move(value));
}

template <typename K, typename V>
void weak_pool<K, V>::perform(perform_handler const &handler) {
    for (auto &entity_pair : this->_all_values) {
        std::string const &entity_name = entity_pair.first;
        for (auto &value_pair : entity_pair.second) {
            K const &key = value_pair.first;
            V value = value_pair.second.lock();
            handler(entity_name, key, value);
        }
    }
}

template <typename K, typename V>
void weak_pool<K, V>::perform_entity(std::string const &entity_name, perform_handler const &handler) {
    if (this->_all_values.count(entity_name)) {
        for (auto &value_pair : this->_all_values.at(entity_name)) {
            K const &key = value_pair.first;
            V value = value_pair.second.lock();
            handler(entity_name, key, value);
        }
    }
}

template <typename K, typename V>
void weak_pool<K, V>::erase(std::string const &entity_name, K const &key) {
    if (this->_all_values.count(entity_name) > 0) {
        erase_if_exists(this->_all_values.at(entity_name), key);
    }
}

template <typename K, typename V>
void weak_pool<K, V>::clear() {
    this->_all_values.clear();
}
}
