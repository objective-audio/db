//
//  yas_db_manager_error.h
//

#pragma once

#include <db/yas_db_error.h>

namespace yas::db {
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
    select_relation_removed_failed,

    make_object_datas_failed,

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

struct manager_error final {
    manager_error(std::nullptr_t);
    explicit manager_error(db::manager_error_type const error_type);
    manager_error(db::manager_error_type const error_type, db::error db_error);

    explicit operator bool() const;

    [[nodiscard]] db::manager_error_type const &type() const;
    [[nodiscard]] db::error const &database_error() const;

   private:
    db::manager_error_type _type;
    db::error _db_error;
};
}  // namespace yas::db

namespace yas {
std::string to_string(db::manager_error_type const &);
std::string to_string(db::manager_error const &);
}  // namespace yas

std::ostream &operator<<(std::ostream &, yas::db::manager_error_type const &);
std::ostream &operator<<(std::ostream &, yas::db::manager_error const &);
