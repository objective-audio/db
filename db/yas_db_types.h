//
//  yas_db_types.h
//

#pragma once

#include <cpp_utils/yas_result.h>
#include <sqlite3.h>
#include <chrono>
#include <string>
#include <unordered_map>

namespace yas::db {
class error;
class row_set;
class value;
class object_id;
class select_option;

static std::string const rowid_field = "rowid";

using update_result_t = result<std::nullptr_t, db::error>;
using query_result_t = result<db::row_set_ptr, db::error>;
using row_result_t = result<sqlite3_int64, db::error>;
using count_result_t = result<int, db::error>;
using integrity_result_t = result<std::nullptr_t, std::string>;

using value_vector_t = std::vector<db::value>;
using value_map_t = std::unordered_map<std::string, db::value>;
using value_vector_map_t = std::unordered_map<std::string, db::value_vector_t>;
using value_map_map_t = std::unordered_map<std::string, db::value_map_t>;
using value_map_vector_t = std::vector<db::value_map_t>;
using value_map_vector_map_t = std::unordered_map<std::string, db::value_map_vector_t>;

using id_vector_t = std::vector<db::object_id>;
using id_vector_map_t = std::unordered_map<std::string, db::id_vector_t>;

using time_point_t = std::chrono::time_point<std::chrono::system_clock, std::chrono::nanoseconds>;
}  // namespace yas::db
