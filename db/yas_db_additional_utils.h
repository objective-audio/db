//
//  yas_db_additional_utils.h
//

#pragma once

#include "yas_db_manager_error.h"
#include "yas_db_additional_protocol.h"
#include "yas_db_utils.h"

namespace yas {
class version;
namespace db {
    class model;
    class fetch_option;
}

// select

namespace db {
    // 指定したsave_id以前で最後のデータをDBから取得する
    db::select_result_t select_last(db::database const &db, db::select_option option, value const &save_id = nullptr,
                                    bool const include_removed = false);
    // アンドゥするためにキャッシュを上書きするデータをDBから取得する
    db::select_result_t select_for_undo(db::database const &db, std::string const &table_name,
                                        db::integer::type const revert_save_id,
                                        db::integer::type const current_save_id);
    // リドゥーするためにキャッシュを上書きするデータをDBから取得する
    db::select_result_t select_for_redo(db::database const &db, std::string const &table_name,
                                        db::integer::type const revert_save_id,
                                        db::integer::type const current_save_id);
    // リバートするためにキャッシュを上書きするデータをDBから取得する
    db::select_result_t select_for_revert(db::database const &db, std::string const &table_name,
                                          db::integer::type const revert_save_id,
                                          db::integer::type const current_save_id);
    // セーブのために、関連先がremoveされたオブジェクトのアトリビュートをDBから取得する
    db::select_result_t select_for_save(db::database const &db, std::string const &entity_table_name,
                                        std::string const &rel_table_name, db::value_vector_t const &tgt_obj_ids);
}

// info

namespace db {
    // DB情報を取得する
    db::manager_info_result_t fetch_info(db::database const &db);
    // DB情報のテーブルを作る
    db::manager_result_t create_info(db::database &db, yas::version const &version);
    // DB上のcur_save_idとlast_save_idを更新する
    db::manager_info_result_t update_info(db::database &db, db::value const &cur_save_id,
                                          db::value const &last_save_id);
    // DB上のcurrent_save_idを更新する
    db::manager_info_result_t update_current_save_id(db::database &db, db::value const &cur_save_id);
    // DB上のversionを更新する
    db::manager_result_t update_version(db::database &db, yas::version const &version);
}

// convert

namespace db {
    // valueからstableなobject_idに変換する
    // relationのloadに使用
    db::id_vector_t to_stable_ids(db::value_vector_t const &);

    // object_idの配列を丸ごとコピーする
    // relationのsaveに使用
    db::id_vector_t copy_ids(db::id_vector_t const &);

    // stableなobject_idからvalueに変換する
    db::value_vector_t to_values(db::id_vector_t const &);

    // object_dataの配列からconst_objectの配列を生成する
    // 全てのエンティティを含む
    db::const_object_vector_map_t to_const_vector_objects(db::model const &model,
                                                          db::object_load_data_vector_map_t const &datas);

    // object_dataの配列からobject_idをキーとしたconst_objectのmapを生成する
    // 全てのエンティティを含む
    db::const_object_map_map_t to_const_map_objects(db::model const &model,
                                                    db::object_load_data_vector_map_t const &datas);

    // select_optionをfetch_optionにして取得
    db::fetch_option to_fetch_option(db::select_option);

    // オブジェクトIDに一致するデータを取得するfetch_optionを取得
    db::fetch_option to_fetch_option(db::integer_set_map_t const &obj_ids);
}

// make

namespace db {
    // managerから返すエラーを簡易的に生成する
    db::manager_result_t make_error_result(db::manager_error_type const &error_type, db::error db_error = nullptr);

    // エンティティ単位で、複数のオブジェクトのアトリビュートの値を元にobject_dataの配列を生成する
    // 内部でDBから関連先の情報を取得している
    db::object_load_data_vector_result_t make_entity_object_load_datas(db::database &db, std::string const &entity_name,
                                                                       db::relation_map_t const &rel_models,
                                                                       db::value_map_vector_t const &entity_attrs);
}

// setup

namespace db {
    // 必要であればDBをマイグレーションする
    db::manager_result_t migrate_db_if_needed(db::database &db, db::model const &model);

    // 新規にDB情報やテーブルをDB上に作成する
    db::manager_result_t create_info_and_tables(db::database &db, db::model const &model);

    // DB上のデータをクリアする
    db::manager_result_t clear_db(db::database &db, db::model const &model);
}

// editing

namespace db {
    // DB上に新規のデータを挿入する
    db::manager_fetch_result_t insert(db::database &db, db::model const &model, db::info const info,
                                      db::value_map_vector_map_t &&values);

    // select_optionでの条件に一致したデータをDBから取得する
    db::manager_fetch_result_t fetch(db::database &db, db::model const &model, db::fetch_option const &fetch_option);

    // DB上のアトリビュートのデータをパージする
    db::update_result_t purge_attributes(db::database &db, std::string const &table_name);
    // DB上の関連のデータをパージする
    db::update_result_t purge_relations(db::database &db, std::string const &table_name,
                                        std::string const &src_table_name);
    // DB上のデータをパージする
    db::manager_result_t purge_db(db::database &db, db::model const &model);

    // 変更のあったデータをDB上に保存する
    db::manager_fetch_result_t save(db::database &db, db::model const &model, db::info const &info,
                                    db::object_save_data_vector_map_t const &changed_datas);
    // 変更のあったデータのうち削除されたオブジェクトを関連から外す
    db::manager_result_t remove_relations_at_save(db::database &db, db::model const &model, db::info const &info,
                                                  db::object_save_data_vector_map_t const &changed_datas);

    // 全てのエンティティの指定したidより大きいsave_idのデータを削除する
    db::manager_result_t delete_next_to_last(db::database &db, db::model const &model, db::value const &save_id);

    // 関連をDBに挿入する。1つの関連の複数のターゲットidをまとめて挿入する
    // アトリビュートをDBに保存した後に関連ごとに呼び出される
    db::manager_result_t insert_relations(db::database &db, db::relation const &rel_model, db::value const &src_pk_id,
                                          db::value const &src_obj_id, db::value_vector_t const &rel_tgt_obj_ids,
                                          db::value const &save_id);
}
}
