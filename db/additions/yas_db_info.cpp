//
//  yas_db_info.cpp
//

#include "yas_db_info.h"

#include "yas_db_sql_utils.h"

using namespace yas;
using namespace yas::db;

info::info(std::string version, db::integer::type const current_save_id, db::integer::type const last_save_id)
    : _version(std::move(version)), _current_save_id(current_save_id), _last_save_id(last_save_id) {
}

info::info(db::value_map_t values)
    : info(values.at(db::version_field).get<db::text>(), values.at(db::current_save_id_field).get<db::integer>(),
           values.at(db::last_save_id_field).get<db::integer>()) {
}

yas::version const &info::version() const {
    return this->_version;
}

db::integer::type const &info::current_save_id() const {
    return this->_current_save_id.get<db::integer>();
}

db::integer::type const &info::last_save_id() const {
    return this->_last_save_id.get<db::integer>();
}

db::integer::type info::next_save_id() const {
    return this->current_save_id() + 1;
}

db::value const &info::current_save_id_value() const {
    return this->_current_save_id;
}

db::value const &info::last_save_id_value() const {
    return this->_last_save_id;
}

db::value info::next_save_id_value() const {
    return db::value{this->next_save_id()};
}

bool info::operator==(info const &rhs) const {
    return this->_version == rhs._version && this->_current_save_id == rhs._current_save_id &&
           this->_last_save_id == rhs._last_save_id;
}

bool info::operator!=(info const &rhs) const {
    return !(*this == rhs);
}

std::string const &info::sql_for_create() {
    static std::string const _sql =
        db::create_table_sql(info_table, {db::version_field, db::current_save_id_field, db::last_save_id_field});
    return _sql;
}

std::string const &info::sql_for_insert() {
    static std::string const _sql =
        db::insert_sql(info_table, {db::version_field, db::current_save_id_field, db::last_save_id_field});
    return _sql;
}

std::string const &info::sql_for_update_version() {
    static std::string const _sql = db::update_sql(info_table, {db::version_field});
    return _sql;
}

std::string const &info::sql_for_update_save_ids() {
    static std::string const _sql = db::update_sql(info_table, {db::current_save_id_field, db::last_save_id_field});
    return _sql;
}

std::string const &info::sql_for_update_current_save_id() {
    static std::string const _sql = db::update_sql(info_table, {db::current_save_id_field});
    return _sql;
}
