//
//  yas_db_manager_utils.h
//

#pragma once

#include "yas_db_manager.h"

namespace yas {
namespace db {
    class relation;
    using relation_map_t = std::unordered_map<std::string, relation>;
    
    using object_data_result_t = result<db::object_data, db::error>;
    using object_data_vector_result_t = result<db::object_data_vector_t, db::error>;
    using value_vector_result_t = result<std::vector<db::value>, db::error>;
    using value_vector_map_result_t = result<db::value_vector_map_t, db::error>;

    db::manager::result_t make_error_result(db::manager::error_type const &error_type, db::error db_error = nullptr);

    db::value_vector_result_t select_relation_target_ids(db::database &db, std::string const &rel_table_name,
                                                         db::value const &save_id, db::value const &src_id);

    db::value_vector_map_result_t select_relation_data(db::database &db, db::relation_map_t const &rel_models,
                                                       db::value const &save_id, db::value const &src_id);

    db::object_data_vector_result_t make_entity_object_datas(db::database &db, std::string const &entity_name,
                                                             db::relation_map_t const &rel_models,
                                                             db::value_map_vector_t const &entity_attrs);

    db::manager::value_result_t select_current_save_id(db::database &db);

    db::manager::result_t delete_next_to_last(db::database &db, db::model const &model,
                                              db::value const &current_save_id);

    db::const_object_vector_map_t to_const_vector_objects(db::model const &model,
                                                          db::object_data_vector_map_t const &datas);

    db::const_object_map_map_t to_const_map_objects(db::model const &model, db::object_data_vector_map_t const &datas);
}
}
