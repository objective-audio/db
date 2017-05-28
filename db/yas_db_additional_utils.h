//
//  yas_db_additional_utils.h
//

#pragma once

#include "yas_db_manager_error.h"
#include "yas_db_additional_protocol.h"
#include "yas_db_utils.h"

namespace yas {
namespace db {
    class model;

    db::select_result_t select_last(db::database const &db, db::select_option option, value const &save_id = nullptr,
                                    bool const include_removed = false);
    db::select_result_t select_undo(db::database const &db, std::string const &table_name,
                                    db::integer::type const revert_save_id, db::integer::type const current_save_id);
    db::select_result_t select_redo(db::database const &db, std::string const &table_name,
                                    db::integer::type const revert_save_id, db::integer::type const current_save_id);
    db::select_result_t select_revert(db::database const &db, std::string const &table_name,
                                      db::integer::type const revert_save_id, db::integer::type const current_save_id);
    db::select_result_t select_relation_removed(db::database const &db, std::string const &entity_table_name,
                                                std::string const &rel_table_name,
                                                db::value_vector_t const &tgt_obj_ids);

    db::select_single_result_t select_db_info(db::database const &db);

    db::update_result_t purge(db::database &db, std::string const &table_name);
    db::update_result_t purge_relation(db::database &db, std::string const &table_name,
                                       std::string const &src_table_name);

    // managerから返すエラーを簡易的に生成する
    db::manager_result_t make_error_result(db::manager_error_type const &error_type, db::error db_error = nullptr);

    // エンティティ単位で、複数のオブジェクトのアトリビュートの値を元にobject_dataの配列を生成する
    // 内部でDBから関連先の情報を取得している
    db::object_data_vector_result_t make_entity_object_datas(db::database &db, std::string const &entity_name,
                                                             db::relation_map_t const &rel_models,
                                                             db::value_map_vector_t const &entity_attrs);

    // カレントセーブIDをDBから取得する
    db::manager_value_result_t select_current_save_id(db::database &db);

    // 全てのエンティティの指定したidより大きいsave_idのデータを削除する
    db::manager_result_t delete_next_to_last(db::database &db, db::model const &model, db::value const &save_id);

    // 関連をDBに挿入する。1つの関連の複数のターゲットidをまとめて挿入する
    // アトリビュートをDBに保存した後に関連ごとに呼び出される
    db::manager_result_t insert_relations(db::database &db, db::relation const &rel_model, db::value const &src_pk_id,
                                          db::value const &src_obj_id, db::value_vector_t const &rel_tgt_obj_ids,
                                          db::value const &save_id);

    // object_dataの配列からconst_objectの配列を生成する
    // 全てのエンティティを含む
    db::const_object_vector_map_t to_const_vector_objects(db::model const &model,
                                                          db::object_data_vector_map_t const &datas);

    // object_dataの配列からobject_idをキーとしたconst_objectのmapを生成する
    // 全てのエンティティを含む
    db::const_object_map_map_t to_const_map_objects(db::model const &model, db::object_data_vector_map_t const &datas);
}
}
