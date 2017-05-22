//
//  yas_db_manager_error.h
//

#pragma once

#include "yas_db_error.h"

namespace yas {
namespace db {
    enum class manager_error_type {
        none,

        begin_transaction_failed,

        create_info_table_failed,
        create_entity_table_failed,
        alter_entity_table_failed,
        create_relation_table_failed,
        create_index_failed,

        insert_info_failed,
        insert_attributes_failed,
        insert_relation_failed,

        update_info_failed,
        update_save_id_failed,

        select_failed,
        select_info_failed,
        select_last_failed,
        select_revert_failed,

        fetch_object_datas_failed,

        delete_failed,
        purge_failed,
        purge_relation_failed,
        vacuum_failed,

        invalid_version_text,
        version_not_found,
        save_id_not_found,
        out_of_range_save_id,
        last_insert_rowid_failed,
    };

    struct manager_error {
        manager_error(std::nullptr_t);
        explicit manager_error(db::manager_error_type const error_type, db::error db_error = nullptr);

        explicit operator bool() const;

        db::manager_error_type const &type() const;
        db::error const &database_error() const;

       private:
        db::manager_error_type _type;
        db::error _db_error;
    };
}
std::string to_string(db::manager_error_type const &);
}
