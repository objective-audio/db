//
//  yas_db_additional_types.h
//

#pragma once

#include <cpp_utils/yas_version.h>
#include <db/yas_db_object_id.h>
#include <db/yas_db_value.h>
#include <db/yas_db_weak_pool.h>

#include <set>
#include <unordered_set>

namespace yas {
template <typename Canceller>
class task;
}

namespace yas::db {
class object;
class const_object;
class attribute;
class relation;
class object_data;
class entity;
class index;
class manager_error;
class info;
class fetch_option;

// for object
using integer_set_t = std::set<db::integer::type>;
using integer_set_map_t = std::unordered_map<std::string, db::integer_set_t>;

using object_map_t = std::unordered_map<db::integer::type, db::object_ptr>;
using object_map_map_t = std::unordered_map<std::string, db::object_map_t>;
using tmp_object_map_t = std::unordered_map<std::string, db::object_ptr>;
using tmp_object_map_map_t = std::unordered_map<std::string, db::tmp_object_map_t>;
using object_vector_t = std::vector<db::object_ptr>;
using object_opt_vector_t = std::vector<std::optional<db::object_ptr>>;
using object_vector_map_t = std::unordered_map<std::string, db::object_vector_t>;
using const_object_map_t = std::unordered_map<db::integer::type, db::const_object_ptr>;
using const_object_map_map_t = std::unordered_map<std::string, db::const_object_map_t>;
using const_object_vector_t = std::vector<db::const_object_ptr>;
using const_object_vector_map_t = std::unordered_map<std::string, db::const_object_vector_t>;
using object_data_vector_t = std::vector<db::object_data>;
using object_data_vector_map_t = std::unordered_map<std::string, db::object_data_vector_t>;

enum class object_status {
    invalid,
    created,
    saved,
    changed,
    updating,
};

struct object_data {
    db::object_id object_id;
    db::value_map_t attributes;
    db::id_vector_map_t relations;
};

// for manager
static std::string const info_table = "db_info";
static std::string const version_field = "version";
static std::string const current_save_id_field = "cur_save_id";
static std::string const last_save_id_field = "last_save_id";

using object_data_vector_result_t = result<db::object_data_vector_t, db::error>;
using value_vector_result_t = result<std::vector<db::value>, db::error>;
using value_vector_map_result_t = result<db::value_vector_map_t, db::error>;

using manager_result_t = result<std::nullptr_t, db::manager_error>;
using manager_vector_result_t = result<db::object_vector_map_t, db::manager_error>;
using manager_map_result_t = result<db::object_map_map_t, db::manager_error>;
using manager_const_vector_result_t = result<db::const_object_vector_map_t, db::manager_error>;
using manager_const_map_result_t = result<db::const_object_map_map_t, db::manager_error>;
using manager_info_result_t = result<db::info, db::manager_error>;
using manager_fetch_result_t = result<db::object_data_vector_map_t, db::manager_error>;

using cancellation_f = std::function<bool(void)>;
using execution_f = std::function<void(task<std::nullptr_t> const &)>;

using entity_count_map_t = std::unordered_map<std::string, std::size_t>;

using insert_count_preparation_f = std::function<db::entity_count_map_t(void)>;
using insert_values_preparation_f = std::function<db::value_map_vector_map_t(void)>;
using fetch_option_preparation_f = std::function<db::fetch_option(void)>;
using fetch_ids_preparation_f = std::function<db::integer_set_map_t(void)>;
using fetch_objects_preparation_f = std::function<db::object_vector_t(void)>;
using fetch_object_map_preparation_f = std::function<db::object_map_map_t(void)>;
using fetch_object_vector_preparation_f = std::function<db::object_vector_map_t(void)>;
using revert_preparation_f = std::function<db::integer::type(void)>;

using completion_f = std::function<void(db::manager_result_t)>;
using vector_completion_f = std::function<void(db::manager_vector_result_t)>;
using map_completion_f = std::function<void(db::manager_map_result_t)>;
using const_vector_completion_f = std::function<void(db::manager_const_vector_result_t)>;
using const_map_completion_f = std::function<void(db::manager_const_map_result_t)>;

static std::function<bool(void)> const no_cancellation = []() { return false; };

// for attribute
static std::string const pk_id_field = "pk_id";
static std::string const object_id_field = "obj_id";
static std::string const save_id_field = "save_id";
static std::string const action_field = "action";

static std::string const insert_action = "insert";
static std::string const update_action = "update";
static std::string const remove_action = "remove";

enum class attribute_type {
    integer,
    real,
    text,
    blob,
};

struct attribute_args final {
    std::string name;
    attribute_type type;
    db::value default_value = nullptr;
    bool not_null = false;
    bool primary = false;
    bool unique = false;
};

using attribute_args_vector_t = std::vector<attribute_args>;

// for relation
static std::string const src_pk_id_field = "src_pk_id";
static std::string const src_obj_id_field = "src_obj_id";
static std::string const tgt_obj_id_field = "tgt_obj_id";

struct relation_args final {
    std::string name;
    std::string target;
    bool const many = false;
};

using relation_args_vector_t = std::vector<relation_args>;

// for entity
using attribute_map_t = std::unordered_map<std::string, db::attribute>;
using relation_map_t = std::unordered_map<std::string, db::relation>;
using string_set_t = std::unordered_set<std::string>;
using string_set_map_t = std::unordered_map<std::string, db::string_set_t>;

struct entity_args final {
    std::string name;
    db::attribute_args_vector_t attributes;
    db::relation_args_vector_t relations;
};

using entity_args_vector_t = std::vector<entity_args>;

// for index

struct index_args final {
    std::string name;
    std::string entity;
    std::vector<std::string> attributes;
};

using index_args_vector_t = std::vector<index_args>;

// for model
using entity_map_t = std::unordered_map<std::string, db::entity>;
using index_map_t = std::unordered_map<std::string, db::index>;

struct model_args final {
    yas::version version;
    std::vector<db::entity_args> entities;
    std::vector<db::index_args> indices;
};
}  // namespace yas::db
