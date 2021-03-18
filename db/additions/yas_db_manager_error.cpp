//
//  yas_db_manager_error.cpp
//

#include "yas_db_manager_error.h"

using namespace yas;
using namespace yas::db;

#pragma mark - error

manager_error::manager_error(std::nullptr_t) : _type(), _db_error(nullptr) {
}

manager_error::manager_error(manager_error_type const error_type) : manager_error(error_type, nullptr) {
}

manager_error::manager_error(manager_error_type const error_type, db::error db_error)
    : _type(error_type), _db_error(std::move(db_error)) {
}

manager_error::operator bool() const {
    return this->_type != manager_error_type::none;
}

manager_error_type const &manager_error::type() const {
    return this->_type;
}

db::error const &manager_error::database_error() const {
    return this->_db_error;
}

std::string yas::to_string(manager_error_type const &error) {
    switch (error) {
        case manager_error_type::begin_transaction_failed:
            return "begin_transaction_failed";
        case manager_error_type::vacuum_failed:
            return "vacuum_failed";
        case manager_error_type::select_info_failed:
            return "select_info_failed";
        case manager_error_type::update_info_failed:
            return "update_info_failed";
        case manager_error_type::version_not_found:
            return "version_not_found";
        case manager_error_type::invalid_version_text:
            return "invalid_version_text";
        case manager_error_type::alter_entity_table_failed:
            return "alter_entity_table_failed";
        case manager_error_type::create_info_table_failed:
            return "create_info_table_failed";
        case manager_error_type::insert_info_failed:
            return "insert_info_failed";
        case manager_error_type::create_entity_table_failed:
            return "create_entity_table_failed";
        case manager_error_type::create_relation_table_failed:
            return "create_relation_table_failed";
        case manager_error_type::create_index_failed:
            return "create_index_failed";
        case manager_error_type::insert_attributes_failed:
            return "insert_attributes_failed";
        case manager_error_type::insert_relation_failed:
            return "insert_relation_failed";
        case manager_error_type::save_id_not_found:
            return "save_id_not_found";
        case manager_error_type::update_save_id_failed:
            return "update_save_id_failed";
        case manager_error_type::delete_failed:
            return "delete_failed";
        case manager_error_type::purge_failed:
            return "purge_failed";
        case manager_error_type::purge_relation_failed:
            return "purge_relation_failed";
        case manager_error_type::select_last_failed:
            return "select_last_failed";
        case manager_error_type::select_revert_failed:
            return "select_revert_failed";
        case manager_error_type::select_relation_removed_failed:
            return "select_relation_removed_failed";
        case manager_error_type::make_object_datas_failed:
            return "make_object_datas_failed";
        case manager_error_type::out_of_range_save_id:
            return "out_of_range_save_id";
        case manager_error_type::select_failed:
            return "select_failed";
        case manager_error_type::last_insert_rowid_failed:
            return "last_insert_rowid_failed";
        case manager_error_type::none:
            return "none";
    }
    return std::string();
}

std::string yas::to_string(manager_error const &error) {
    if (error) {
        return "{type:" + to_string(error.type()) + ", database_error" + to_string(error.database_error()) + "}";
    } else {
        return "null";
    }
}
