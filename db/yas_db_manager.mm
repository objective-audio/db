//
//  yas_db_manager.cpp
//

#include "yas_db_manager.h"
#include "yas_db_additional_utils.h"
#include "yas_db_attribute.h"
#include "yas_db_entity.h"
#include "yas_db_model.h"
#include "yas_db_object_utils.h"
#include "yas_db_relation.h"
#include "yas_db_select_option.h"
#include "yas_db_sql_utils.h"
#include "yas_db_utils.h"
#include "yas_db_index.h"
#include "yas_db_database.h"
#include "yas_each_index.h"
#include "yas_objc_macros.h"
#include "yas_observing.h"
#include "yas_operation.h"
#include "yas_result.h"
#include "yas_stl_utils.h"
#include "yas_unless.h"
#include "yas_version.h"
#include "yas_db_info.h"
#include "yas_db_fetch_option.h"

using namespace yas;

#pragma mark - change_info

db::manager::change_info::change_info(std::nullptr_t) : object(nullptr) {
}

db::manager::change_info::change_info(db::object const &object) : object(object) {
}

#pragma mark - impl

struct db::manager::impl : public base::impl, public object_observable::impl {
    db::database _database;
    db::model _model;
    operation_queue _op_queue;
    std::size_t _suspend_count = 0;
    db::weak_object_map_map_t _cached_objects;
    db::object_deque_map_t _inserted_objects;
    db::object_map_map_t _changed_objects;
    db::info _db_info = db::null_info();
    db::manager::subject_t _subject;
    dispatch_queue_t _dispatch_queue;

    impl(std::string const &path, db::model const &model, dispatch_queue_t const dispatch_queue,
         std::size_t const priority_count)
        : _database(path),
          _model(model),
          _dispatch_queue(dispatch_queue),
          _op_queue(priority_count),
          _cached_objects() {
        yas_dispatch_queue_retain(dispatch_queue);
    }

    ~impl() {
        yas_dispatch_queue_release(dispatch_queue);
    }

    // データベースに保存せず仮にオブジェクトを生成する
    // この時点ではobject_idやsave_idは振られていない
    db::object insert_object(std::string const entity_name) {
        db::object object{cast<db::manager>(), this->_model.entity(entity_name)};

        object.manageable().load_insertion_data();

        if (this->_inserted_objects.count(entity_name) == 0) {
            this->_inserted_objects.insert(std::make_pair(entity_name, db::object_deque_t{}));
        }

        this->_inserted_objects.at(entity_name).push_back(object);

        return object;
    }

    // 1つのオブジェクトにデータベースから読み込まれたデータをロードする
    bool load_and_cache_object_from_data(db::object &object, std::string const &entity_name,
                                         db::object_data const &data, bool const force) {
        if (this->_cached_objects.count(entity_name) == 0) {
            this->_cached_objects.emplace(entity_name, db::weak_object_map_t{});
        }

        auto manager = cast<db::manager>();
        auto &entity_cached_objects = this->_cached_objects.at(entity_name);

        if (data.attributes.count(db::object_id_field) > 0) {
            if (auto const &object_id_value = data.attributes.at(db::object_id_field)) {
                auto const &object_id = object_id_value.get<db::integer>();

                if (object) {
                    // オブジェクトがある場合（挿入された場合）キャッシュに追加
                    entity_cached_objects.emplace(object_id, to_weak(object));
                } else {
                    // オブジェクトがない場合（挿入でない場合）
                    if (entity_cached_objects.count(object_id) > 0) {
                        // キャッシュにオブジェクトがあるなら取得
                        object = entity_cached_objects.at(object_id).lock();
                        if (!object) {
                            // キャッシュ内のweakのオブジェクトの本体が解放されているのはおかしい
                            throw "cached object is released. entity_name (" + entity_name + ") object_id (" +
                                std::to_string(object_id) + ")";
                        }
                    }

                    if (!object) {
                        // キャッシュにオブジェクトがないなら、オブジェクトを生成してキャッシュに追加
                        object = db::object{manager, this->_model.entity(entity_name)};
                        entity_cached_objects.emplace(object_id, to_weak(object));
                    }
                }

                // オブジェクトにデータをロード
                object.manageable().load_data(data, force);

                return true;
            }
        } else {
            throw "object_id not found.";
        }

        return false;
    }

    // 複数のエンティティのデータをロードしてキャッシュする
    // ロードされたオブエジェクトはエンティティごとに順番がある状態で返される
    db::object_vector_map_t load_and_cache_vector_object_from_datas(db::object_data_vector_map_t const &datas,
                                                                    bool const force, bool const is_save) {
        db::object_vector_map_t loaded_objects;
        for (auto const &entity_pair : datas) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_datas = entity_pair.second;

            db::object_vector_t objects;
            objects.reserve(entity_datas.size());

            for (auto const &data : entity_datas) {
                auto object = db::null_object();
                if (is_save && this->_inserted_objects.count(entity_name) > 0) {
                    // セーブ時で仮に挿入されたオブジェクトがある場合にオブジェクトを取得
                    auto &entity_objects = this->_inserted_objects.at(entity_name);
                    if (entity_objects.size() > 0) {
                        // 前から順に消していけば一致している？
                        // 後から挿入されたオブジェクトが間違えて消されることはないか？
                        // 挿入されたときのセーブ以外にも呼ばれたりしないか？
                        object = entity_objects.front();
                        entity_objects.pop_front();

                        if (entity_objects.size() == 0) {
                            this->_inserted_objects.erase(entity_name);
                        }
                    }
                }

                // オブジェクトにデータをロード。挿入でなければobjectはnullで、必要に応じて内部でキャッシュに追加される
                if (this->load_and_cache_object_from_data(object, entity_name, data, force)) {
                    objects.emplace_back(std::move(object));
                }
            }

            loaded_objects.emplace(entity_name, std::move(objects));
        }
        return loaded_objects;
    }

    // 複数のエンティティのデータをロードしてキャッシュする
    // ロードされたオブジェクトはエンティティごとにobject_idをキーとしたmapで返される
    db::object_map_map_t load_and_cache_map_object_from_datas(db::object_data_vector_map_t const &datas,
                                                              bool const force) {
        db::object_map_map_t loaded_objects;
        for (auto const &entity_pair : datas) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_datas = entity_pair.second;

            db::object_map_t objects;
            objects.reserve(entity_datas.size());

            for (auto const &data : entity_datas) {
                auto object = db::null_object();
                if (this->load_and_cache_object_from_data(object, entity_name, data, force)) {
                    objects.emplace(object.object_id().get<db::integer>(), std::move(object));
                }
            }

            loaded_objects.emplace(entity_name, std::move(objects));
        }
        return loaded_objects;
    }

    // キャッシュされている全てのオブジェクトをクリアする
    void clear_cached_objects() {
        for (auto &entity_pair : this->_cached_objects) {
            for (auto &object_pair : entity_pair.second) {
                if (auto object = object_pair.second.lock()) {
                    object.manageable().clear_data();
                }
            }
        }
        this->_cached_objects.clear();
    }

    // キャッシュされている全てのオブジェクトをパージする（save_idを全て1にする）
    // データベースのパージが成功した時に呼ばれる
    void purge_cached_objects() {
        // キャッシュされたオブジェクトのセーブIDを全て1にする
        db::value const one_value{db::integer::type{1}};

        for (auto &entity_pair : this->_cached_objects) {
            for (auto &object_pair : entity_pair.second) {
                if (auto object = object_pair.second.lock()) {
                    object.manageable().load_save_id(one_value);
                }
            }
        }
    }

    // データベース情報を置き換える
    void set_db_info(db::info &&info) {
        this->_db_info = std::move(info);

        if (this->_subject.has_observer()) {
            this->_subject.notify(db::manager::method::db_info_changed);
        }
    }

    // データベースに保存するために、全てのエンティティで変更のあったオブジェクトのobject_dataを取得する
    db::object_data_vector_map_t changed_datas_for_save() {
        db::object_data_vector_map_t changed_datas;

        for (auto const &entity_pair : this->_model.entities()) {
            // エンティティごとの処理
            auto const &entity_name = entity_pair.first;

            // 仮に挿入されたオブジェクトの数
            std::size_t const inserted_count =
                this->_inserted_objects.count(entity_name) ? this->_inserted_objects.at(entity_name).size() : 0;
            // 値に変更のあったオブジェクトの数
            std::size_t const changed_count =
                this->_changed_objects.count(entity_name) ? this->_changed_objects.at(entity_name).size() : 0;
            // 挿入か変更のあったオブジェクトの数の合計
            std::size_t const total_count = inserted_count + changed_count;

            // 挿入も変更もされていなければスキップ
            if (total_count == 0) {
                continue;
            }

            db::object_data_vector_t entity_datas;
            entity_datas.reserve(total_count);

            if (inserted_count > 0) {
                // 挿入されたオブジェクトからデータベース用のデータを取得
                auto const &entity_objects = this->_inserted_objects.at(entity_name);

                for (auto const &object : entity_objects) {
                    auto data = object.data_for_save();
                    if (data.attributes.size() > 0) {
                        entity_datas.emplace_back(std::move(data));
                    } else {
                        throw "object_data.attributes is empty.";
                    }
                }
            }

            if (changed_count > 0) {
                // 変更されたオブジェクトからデータベース用のデータを取得
                auto &entity_objects = this->_changed_objects.at(entity_name);

                for (auto &object_pair : entity_objects) {
                    auto &object = object_pair.second;
                    auto data = object.data_for_save();
                    if (data.attributes.size() > 0) {
                        entity_datas.emplace_back(std::move(data));
                    } else {
                        throw "object_data.attributes is empty.";
                    }
                    object.manageable().set_status(db::object_status::updating);
                }
            }

            changed_datas.emplace(entity_name, std::move(entity_datas));
        }

        return changed_datas;
    }

    // リセットするために、全てのエンティティで変更のあったオブジェクトのobject_idを取得する
    db::integer_set_map_t changed_object_ids_for_reset() {
        db::integer_set_map_t changed_obj_ids;

        for (auto const &entity_pair : this->_changed_objects) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_objects = entity_pair.second;

            db::integer_set_t entity_ids;

            for (auto const &object_pair : entity_objects) {
                auto const &object = object_pair.second;
                entity_ids.insert(object.object_id().get<db::integer>());
            }

            if (entity_ids.size() > 0) {
                changed_obj_ids.emplace(entity_name, std::move(entity_ids));
            }
        }

        return changed_obj_ids;
    }

    // object_datasに含まれるオブジェクトIDと一致するものは_changed_objectsから取り除く
    // データベースに保存された後などに呼ばれる。
    void erase_changed_objects(db::object_data_vector_map_t const &object_datas) {
        for (auto const &entity_pair : object_datas) {
            auto const &entity_name = entity_pair.first;
            if (this->_changed_objects.count(entity_name) > 0) {
                auto const &entity_objects = entity_pair.second;
                if (entity_objects.size() > 0) {
                    auto &changed_entity_objects = this->_changed_objects.at(entity_name);
                    for (auto const &obj_data : entity_objects) {
                        erase_if_exists(changed_entity_objects,
                                        obj_data.attributes.at(db::object_id_field).get<db::integer>());
                    }

                    if (changed_entity_objects.size() == 0) {
                        this->_changed_objects.erase(entity_name);
                    }
                }
            }
        }
    }

    // キャッシュされた単独のオブジェクトをエンティティ名とオブジェクトIDを指定して取得する
    db::object cached_object(std::string const &entity_name, db::integer::type object_id) {
        if (this->_cached_objects.count(entity_name) > 0) {
            auto const &entity_objects = this->_cached_objects.at(entity_name);
            if (entity_objects.count(object_id) > 0) {
                if (auto const &weak_object = entity_objects.at(object_id)) {
                    if (auto object = weak_object.lock()) {
                        return object;
                    }
                }
            }
        }
        return db::null_object();
    }

    // オブジェクトに変更があった時の処理
    void _object_did_change(db::object const &object) {
        auto const &entity_name = object.entity_name();

        if (object.status() == db::object_status::inserted) {
            // 仮に挿入された状態の場合
            if (this->_inserted_objects.count(entity_name) > 0 && object.is_removed()) {
                // オブジェクトが削除されていたら、_inserted_objectsからも削除
                erase_if(this->_inserted_objects.at(entity_name),
                         [&object](auto const &inserted_object) { return inserted_object == object; });
            }
        } else {
            // 挿入されたのではない場合
            if (this->_changed_objects.count(entity_name) == 0) {
                // _changed_objectsにエンティティのmapがなければ生成する
                this->_changed_objects.insert(std::make_pair(entity_name, db::object_map_t{}));
            }

            // _changed_objectsにオブジェクトを追加
            auto const &obj_id = object.object_id().get<db::integer>();
            if (this->_changed_objects.at(entity_name).count(obj_id) == 0) {
                this->_changed_objects.at(entity_name).emplace(obj_id, object);
            }
        }

        if (object.is_removed()) {
            // オブジェクトが削除されていたら逆関連も削除する
            for (auto const &entity_pair : this->_model.entity(entity_name).inverse_relation_names) {
                auto const &inv_entity_name = entity_pair.first;
                if (this->_cached_objects.count(inv_entity_name) > 0) {
                    for (auto &pair : this->_cached_objects.at(inv_entity_name)) {
                        auto inv_rel_obj = pair.second.lock();
                        for (auto const &inv_rel_name : entity_pair.second) {
                            inv_rel_obj.remove_relation_id(inv_rel_name, object.object_id());
                        }
                    }
                }
            }
        }

        // オブジェクトが変更された通知を送信
        if (this->_subject.has_observer()) {
            this->_subject.notify(db::manager::method::object_changed, db::manager::change_info{object});
        }
    }

    // オブジェクトが解放された時の処理
    void _object_did_erase(std::string const &entity_name, db::integer::type const object_id) {
        if (this->_cached_objects.count(entity_name) > 0) {
            // キャッシュからオブジェクトを削除する
            // キャッシュにはweakで持っている
            erase_if_exists(this->_cached_objects.at(entity_name), object_id);
        }
    }

    // バックグラウンドでデータベースの処理をする
    void execute(execution_f &&execution, operation_option_t &&option) {
        auto op_lambda = [execution = std::move(execution), manager = cast<manager>()](operation const &op) mutable {
            if (!op.is_canceled()) {
                auto &db = manager.impl_ptr<impl>()->_database;
                db.open();
                execution(op);
                db.close();
            }
        };

        this->_op_queue.push_back(operation{std::move(op_lambda), std::move(option)});
    }

    // バックグラウンドでマネージャのセットアップ処理をする
    void execute_setup(std::function<void(db::manager_result_t &&, db::info &&)> &&completion,
                       operation_option_t &&option) {
        auto execution = [completion = std::move(completion), manager = cast<manager>()](operation const &op) mutable {
            db::database &db = manager.database();
            db::model const &model = manager.model();

            db::manager_result_t state{nullptr};

            if (auto begin_result = db::begin_transaction(db)) {
                // トランザクションを開始
                if (db::table_exists(db, db::info_table)) {
                    // infoのテーブルが存在している場合
                    state = db::migrate_db_if_needed(db, model);
                } else {
                    // infoのテーブルが存在していない場合は、新規にテーブルを作成する
                    state = db::create_info_and_tables(db, model);
                }

                // トランザクション終了
                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                }
            } else {
                state = db::make_error_result(db::manager_error_type::begin_transaction_failed,
                                              std::move(begin_result.error()));
            }

            db::info info = db::null_info();

            if (state) {
                if (auto select_result = db::select_db_info(db)) {
                    info = std::move(select_result.value());
                } else {
                    state = db::manager_result_t{select_result.error()};
                }
            }

            completion(std::move(state), std::move(info));
        };

        this->execute(execution, std::move(option));
    }

    // バックグラウンドでデータベース上のデータをクリアする
    void execute_clear(std::function<void(db::manager_result_t &&, db::info &&)> &&completion,
                       operation_option_t &&option) {
        auto execution = [completion = std::move(completion), manager = cast<manager>()](operation const &op) mutable {
            auto &db = manager.database();
            auto const &model = manager.model();

            db::info db_info = db::null_info();
            db::manager_result_t state{nullptr};

            // トランザクション開始
            if (auto begin_result = db::begin_transaction(db)) {
                // DBをクリアする
                if (auto clear_result = db::clear_db(db, model)) {
                    // infoをクリア。セーブIDを0にする
                    db::value const zero_value{db::integer::type{0}};
                    if (auto update_result = db::update_db_info(db, zero_value, zero_value)) {
                        db_info = std::move(update_result.value());
                    } else {
                        state = db::manager_result_t{std::move(update_result.error())};
                    }
                } else {
                    state = std::move(clear_result);
                }

                // トランザクション終了
                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                    db_info = db::null_info();
                }
            } else {
                state = db::make_error_result(db::manager_error_type::begin_transaction_failed,
                                              std::move(begin_result.error()));
            }

            completion(std::move(state), std::move(db_info));
        };

        this->execute(execution, std::move(option));
    }

    // バックグラウンドでデータベース上のデータをパージする
    void execute_purge(std::function<void(db::manager_result_t &&, db::info &&)> &&completion,
                       operation_option_t &&option) {
        auto execution = [completion = std::move(completion), manager = cast<manager>()](operation const &op) mutable {
            auto &db = manager.database();
            auto const &model = manager.model();

            db::info db_info = db::null_info();
            db::manager_result_t state{nullptr};

            // トランザクション開始
            if (auto begin_result = db::begin_transaction(db)) {
                if (auto purge_result = db::purge_db(db, model)) {
                    // infoをクリア。セーブIDを1にする
                    db::value const one_value = db::value{db::integer::type{1}};
                    if (auto update_result = db::update_db_info(db, one_value, one_value)) {
                        db_info = std::move(update_result.value());
                    } else {
                        state = db::manager_result_t{std::move(update_result.error())};
                    }
                } else {
                    state = std::move(purge_result);
                }

                // トランザクション終了
                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                }
            } else {
                state = db::make_error_result(db::manager_error_type::begin_transaction_failed,
                                              std::move(begin_result.error()));
            }

            if (state) {
                // バキュームする（バキュームはトランザクション中はできない）
                if (auto ul = unless(db.execute_update(db::vacuum_sql()))) {
                    state = db::make_error_result(db::manager_error_type::vacuum_failed, std::move(ul.value.error()));
                }
            }

            completion(std::move(state), std::move(db_info));
        };

        this->execute(execution, std::move(option));
    }

    // バックグラウンドでデータベース上にオブジェクトデータを挿入する
    void execute_insert(
        insert_preparation_values_f &&preparation,
        std::function<void(db::manager_result_t &&, db::object_data_vector_map_t &&, db::info &&)> &&completion,
        operation_option_t &&option) {
        auto execution =
            [preparation = std::move(preparation), completion = std::move(completion),
             manager = cast<manager>()](operation const &op) mutable {
            // 挿入するオブジェクトのデータをメインスレッドで準備する
            db::value_map_vector_map_t values;
            auto preparation_on_main = [&values, &preparation]() { values = preparation(); };
            dispatch_sync(manager.dispatch_queue(), std::move(preparation_on_main));

            auto &db = manager.database();
            auto const &model = manager.model();

            db::info ret_db_info = db::null_info();
            object_data_vector_map_t inserted_datas;

            db::manager_result_t state{nullptr};

            if (auto begin_result = db::begin_transaction(db)) {
                // トランザクション開始

                // DB情報を取得する
                db::info info = db::null_info();
                if (auto info_result = db::select_db_info(db)) {
                    info = std::move(info_result.value());
                } else {
                    state = db::manager_result_t{std::move(info_result.error())};
                }

                // DB上に新規にデータを挿入する
                if (auto insert_result = db::insert(db, model, info, std::move(values))) {
                    inserted_datas = std::move(insert_result.value());
                } else {
                    state = db::manager_result_t{std::move(insert_result.error())};
                }

                if (state) {
                    // DB情報を更新する
                    auto const next_save_id = info.next_save_id_value();
                    if (auto update_result = db::update_db_info(db, next_save_id, next_save_id)) {
                        ret_db_info = std::move(update_result.value());
                    } else {
                        state = db::manager_result_t{std::move(update_result.error())};
                    }
                }

                // トランザクション終了
                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                    inserted_datas.clear();
                }
            } else {
                state = db::make_error_result(db::manager_error_type::begin_transaction_failed,
                                              std::move(begin_result.error()));
            }

            // 結果を返す
            completion(std::move(state), std::move(inserted_datas), std::move(ret_db_info));
        };

        this->execute(execution, std::move(option));
    }

    // バックグラウンドでデータベースからオブジェクトデータを取得する。条件はselect_optionで指定。単独のエンティティのみ
    void execute_fetch_object_datas(
        fetch_preparation_option_f &&preparation,
        std::function<void(db::manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas)> &&completion,
        operation_option_t &&op_option) {
        auto execution =
            [preparation = std::move(preparation), completion = std::move(completion),
             manager = cast<db::manager>()](operation const &) mutable {
            // データベースからデータを取得する条件をメインスレッドで準備する
            db::fetch_option fetch_option;
            auto preparation_on_main = [&fetch_option, &preparation]() { fetch_option = preparation(); };
            dispatch_sync(manager.dispatch_queue(), std::move(preparation_on_main));

            auto &db = manager.database();
            auto const &model = manager.model();
            db::manager_result_t state{nullptr};
            db::object_data_vector_map_t fetched_datas;

            if (auto begin_result = db::begin_transaction(db)) {
                // トランザクション開始
                if (auto fetch_result = db::fetch(db, model, fetch_option)) {
                    fetched_datas = std::move(fetch_result.value());
                } else {
                    state = db::manager_result_t{std::move(fetch_result.error())};
                }

                // トランザクション終了
                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                    fetched_datas.clear();
                }
            } else {
                state = db::make_error_result(db::manager_error_type::begin_transaction_failed,
                                              std::move(begin_result.error()));
            }

            // 結果を返す
            completion(std::move(state), std::move(fetched_datas));
        };

        this->execute(execution, std::move(op_option));
    }

    // バックグラウンドでデータベースからオブジェクトデータを取得する。条件はobject_idで指定。単独のエンティティのみ
    void execute_fetch_object_datas(
        fetch_preparation_ids_f &&ids_preparation,
        std::function<void(db::manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas)> &&completion,
        operation_option_t &&op_option) {
        fetch_preparation_option_f opt_preparation = [ids_preparation = std::move(ids_preparation)]() {
            return db::to_fetch_option(ids_preparation());
        };

        this->execute_fetch_object_datas(std::move(opt_preparation), std::move(completion), std::move(op_option));
    }

    // バックグラウンドでデータベースにオブジェクトの変更を保存する
    void execute_save(std::function<void(db::manager_result_t &&state, db::object_data_vector_map_t &&saved_datas,
                                         db::info &&db_info)> &&completion,
                      operation_option_t &&option) {
        auto execution = [completion = std::move(completion), manager = cast<manager>()](operation const &) mutable {
            db::object_data_vector_map_t changed_datas;
            // 変更のあったデータをメインスレッドで取得する
            auto manager_impl = manager.impl_ptr<impl>();
            auto get_change_lambda = [&manager_impl, &changed_datas]() {
                changed_datas = manager_impl->changed_datas_for_save();
            };
            dispatch_sync(manager.dispatch_queue(), get_change_lambda);

            auto &db = manager.database();
            auto const &model = manager.model();

            db::info db_info = db::null_info();
            db::object_data_vector_map_t saved_datas;

            db::manager_result_t state{nullptr};

            if (changed_datas.size() > 0) {
                if (auto begin_result = db::begin_transaction(db)) {
                    // トランザクション開始
                    auto current_save_id = db::null_value();
                    auto next_save_id = db::null_value();
                    auto last_save_id = db::null_value();

                    // データベースからセーブIDを取得する
                    if (auto select_result = db::select_db_info(db)) {
                        auto const &db_info = select_result.value();
                        current_save_id = db_info.current_save_id_value();
                        next_save_id = db::value{current_save_id.get<db::integer>() + 1};
                        last_save_id = db_info.last_save_id_value();
                    } else {
                        state = db::manager_result_t{std::move(select_result.error())};
                    }

                    if (state) {
                        // ラストのセーブIDよりカレントが前ならカレントより後のデータは削除する
                        if (current_save_id.get<db::integer>() < last_save_id.get<db::integer>()) {
                            state = db::delete_next_to_last(db, model, current_save_id);
                        }
                    } else {
                        state = db::make_error_result(db::manager_error_type::save_id_not_found);
                    }

                    if (state) {
                        auto const save_id_pair = std::make_pair(db::save_id_field, next_save_id);

                        for (auto const &entity_pair : changed_datas) {
                            auto const &entity_name = entity_pair.first;
                            auto const &changed_entity_datas = entity_pair.second;
                            auto const entity_insert_sql = manager.model().entity(entity_name).sql_for_insert();
                            auto const &rel_models = manager.model().relations(entity_name);

                            db::object_data_vector_t entity_saved_datas;

                            for (auto data : changed_entity_datas) {
                                // 保存するデータのアトリビュートのidは削除する（rowidなのでいらない）
                                erase_if_exists(data.attributes, db::pk_id_field);
                                // 保存するデータのセーブIDを今セーブするIDに置き換える
                                replace(data.attributes, db::save_id_field, next_save_id);

                                if (data.attributes.count(db::object_id_field) == 0) {
                                    // 保存するデータにまだオブジェクトIDがなければデータベース上の最大値+1をセットする
                                    db::integer::type obj_id = 0;
                                    if (auto max_value = db::max(db, entity_name, db::object_id_field)) {
                                        obj_id = max_value.get<db::integer>();
                                    }
                                    replace(data.attributes, db::object_id_field, db::value{obj_id + 1});
                                }

                                // データベースにアトリビュートのデータを挿入する
                                if (auto ul = unless(db.execute_update(entity_insert_sql, data.attributes))) {
                                    state = db::make_error_result(db::manager_error_type::insert_attributes_failed,
                                                                  std::move(ul.value.error()));
                                }

                                if (state) {
                                    // 挿入したデータのrowidを取得
                                    if (auto row_result = db.last_insert_rowid()) {
                                        auto const src_pk_id = db::value{std::move(row_result.value())};
                                        auto const src_obj_id = data.attributes.at(db::object_id_field);

                                        for (auto const &rel_pair : data.relations) {
                                            // データベースに関連のデータを挿入する
                                            auto const &rel_model = rel_models.at(rel_pair.first);
                                            auto const &rel_tgt_obj_ids = rel_pair.second;
                                            if (auto ul =
                                                    unless(db::insert_relations(db, rel_model, src_pk_id, src_obj_id,
                                                                                rel_tgt_obj_ids, next_save_id))) {
                                                state = std::move(ul.value);
                                                break;
                                            }
                                        }
                                    } else {
                                        state = db::make_error_result(db::manager_error_type::last_insert_rowid_failed,
                                                                      std::move(row_result.error()));
                                    }
                                }

                                if (state) {
                                    entity_saved_datas.emplace_back(std::move(data));
                                }
                            }

                            if (!state) {
                                break;
                            }

                            saved_datas.emplace(entity_name, std::move(entity_saved_datas));
                        }
                    }

                    if (state) {
                        // オブジェクトが削除された場合に逆関連があったらデータベース上で関連を外す
                        for (auto const &entity_pair : changed_datas) {
                            // エンティティごとの処理
                            auto const &entity_name = entity_pair.first;
                            auto const &changed_entity_datas = entity_pair.second;
                            auto const &inv_rel_names = manager.model().entity(entity_name).inverse_relation_names;

                            if (inv_rel_names.size() == 0) {
                                // 逆関連が無ければスキップ
                                continue;
                            }

                            // 削除されたobject_idを取得
                            db::value_vector_t tgt_obj_ids;
                            tgt_obj_ids.reserve(changed_entity_datas.size());

                            for (db::object_data const &data : changed_entity_datas) {
                                auto const &action = data.attributes.at(db::action_field);
                                if (action.get<db::text>() != db::remove_action) {
                                    // 削除されていなければスキップ
                                    continue;
                                }

                                tgt_obj_ids.push_back(data.attributes.at(db::object_id_field));
                            }

                            if (tgt_obj_ids.size() == 0) {
                                // 削除されたオブジェクトがなければスキップ
                                continue;
                            }

                            for (auto const &inv_entity_pair : inv_rel_names) {
                                std::string const &inv_entity_name = inv_entity_pair.first;
                                db::string_set_t const &rel_names = inv_entity_pair.second;

                                db::value_map_map_t entity_attrs_map;

                                // tgt_obj_idsが関連先に含まれているオブジェクトのアトリビュートを取得
                                for (auto const &rel_name : rel_names) {
                                    auto const &rel = model.relation(inv_entity_name, rel_name);
                                    if (auto select_result = db::select_relation_removed(db, inv_entity_name,
                                                                                         rel.table_name, tgt_obj_ids)) {
                                        for (auto const &attr : select_result.value()) {
                                            std::string obj_id_str = to_string(attr.at(db::object_id_field));
                                            if (entity_attrs_map.count(obj_id_str) == 0) {
                                                // object_idが被らないものだけ追加する。必ず最後のデータが来ているはず。
                                                entity_attrs_map.emplace(std::move(obj_id_str), std::move(attr));
                                            }
                                        }
                                    } else {
                                        state = db::make_error_result(
                                            db::manager_error_type::select_relation_removed_failed,
                                            std::move(select_result.error()));
                                        break;
                                    }
                                }

                                db::object_data_vector_t inv_removed_datas;

                                if (state && entity_attrs_map.size() > 0) {
                                    // アトリビュートを元に関連を取得する
                                    // mapからvectorへ変換
                                    db::value_map_vector_t entity_attrs_vec = to_vector<db::value_map_t>(
                                        entity_attrs_map, [](auto &pair) { return std::move(pair.second); });

                                    auto const &rel_models = model.relations(inv_entity_name);
                                    if (auto obj_datas_result = db::make_entity_object_datas(
                                            db, inv_entity_name, rel_models, entity_attrs_vec)) {
                                        // 同じidのオブジェクトは上書きかスキップする？
                                        // すでにsaveしたものは被っていないはず
                                        inv_removed_datas = std::move(obj_datas_result.value());
                                    } else {
                                        state = db::make_error_result(db::manager_error_type::make_object_datas_failed,
                                                                      std::move(obj_datas_result.error()));
                                        break;
                                    }
                                }

                                if (state && inv_removed_datas.size() > 0) {
                                    auto const &entity_insert_sql = model.entity(inv_entity_name).sql_for_insert();
                                    auto const &rel_models = model.relations(inv_entity_name);

                                    for (auto &obj_data : inv_removed_datas) {
                                        // 保存するデータのアトリビュートのidは削除する（rowidなのでいらない）
                                        erase_if_exists(obj_data.attributes, db::pk_id_field);
                                        // 保存するデータのセーブIDを今セーブするIDに置き換える
                                        replace(obj_data.attributes, db::save_id_field, next_save_id);
                                        // データベースにアトリビュートのデータを挿入する
                                        if (auto ul =
                                                unless(db.execute_update(entity_insert_sql, obj_data.attributes))) {
                                            state =
                                                db::make_error_result(db::manager_error_type::insert_attributes_failed,
                                                                      std::move(ul.value.error()));
                                            break;
                                        }

                                        // pk_idを取得してセットする
                                        if (auto row_result = db.last_insert_rowid()) {
                                            auto const src_pk_id = db::value{std::move(row_result.value())};
                                            auto const src_obj_id = obj_data.attributes.at(db::object_id_field);

                                            for (auto const &rel_pair : obj_data.relations) {
                                                // データベースに関連のデータを挿入する
                                                auto const &rel_model = rel_models.at(rel_pair.first);
                                                auto const rel_tgt_obj_ids =
                                                    filter(rel_pair.second, [&tgt_obj_ids](auto const &obj_id) {
                                                        return !contains(tgt_obj_ids, obj_id);
                                                    });
                                                if (rel_tgt_obj_ids.size() > 0) {
                                                    if (auto ul = unless(
                                                            db::insert_relations(db, rel_model, src_pk_id, src_obj_id,
                                                                                 rel_tgt_obj_ids, next_save_id))) {
                                                        state = std::move(ul.value);
                                                        break;
                                                    }
                                                }
                                            }
                                        } else {
                                            state =
                                                db::make_error_result(db::manager_error_type::last_insert_rowid_failed,
                                                                      std::move(row_result.error()));
                                            break;
                                        }
                                    }
                                }
                            }

                            if (!state) {
                                break;
                            }
                        }
                    }

                    if (state) {
                        // infoの更新
                        if (auto update_result = db::update_db_info(db, next_save_id, next_save_id)) {
                            db_info = std::move(update_result.value());
                        } else {
                            state = db::manager_result_t{std::move(update_result.error())};
                        }
                    }

                    // トランザクション終了
                    if (state) {
                        db::commit(db);
                    } else {
                        db::rollback(db);
                        saved_datas.clear();
                    }
                } else {
                    state = db::make_error_result(db::manager_error_type::begin_transaction_failed,
                                                  std::move(begin_result.error()));
                }
            }

            if (state && !db_info) {
                if (auto select_result = db::select_db_info(db)) {
                    db_info = std::move(select_result.value());
                } else {
                    state = db::manager_result_t{std::move(select_result.error())};
                }
            }

            completion(std::move(state), std::move(saved_datas), std::move(db_info));
        };

        this->execute(execution, std::move(option));
    }

    // バックグラウンドでリバートする
    void execute_revert(db::manager::revert_preparation_f preparation,
                        std::function<void(db::manager_result_t &&state, db::object_data_vector_map_t &&reverted_datas,
                                           db::info &&db_info)> &&completion,
                        operation_option_t &&option) {
        auto execution =
            [preparation = std::move(preparation), completion = std::move(completion),
             manager = cast<db::manager>()](operation const &) mutable {
            // リバートする先のセーブIDをメインスレッドで準備する
            db::integer::type rev_save_id;
            auto preparation_on_main = [&rev_save_id, &preparation]() { rev_save_id = preparation(); };
            dispatch_sync(manager.dispatch_queue(), std::move(preparation_on_main));

            auto &db = manager.database();

            db::manager_result_t state{nullptr};

            db::value_map_vector_map_t reverted_attrs;
            db::object_data_vector_map_t reverted_datas;
            db::info ret_db_info = db::null_info();

            if (auto begin_result = db::begin_transaction(db)) {
                // トランザクション開始

                // カレントとラストのセーブIDをデータベースから取得する
                db::integer::type last_save_id = 0;
                db::integer::type current_save_id = 0;

                if (auto select_result = db::select_db_info(db)) {
                    auto const &db_info = select_result.value();
                    current_save_id = db_info.current_save_id();
                    last_save_id = db_info.last_save_id();
                } else {
                    state = db::manager_result_t{std::move(select_result.error())};
                }

                auto const &entity_models = manager.model().entities();

                if (rev_save_id == current_save_id || last_save_id < rev_save_id) {
                    // リバートしようとするセーブIDがカレントと同じかラスト以降ならエラー
                    state = db::make_error_result(db::manager_error_type::out_of_range_save_id);
                } else {
                    for (auto const &entity_model_pair : entity_models) {
                        auto const &entity_name = entity_model_pair.first;
                        // リバートするためのデータをデータベースから取得する
                        // カレントとの位置によってredoかundoが内部で呼ばれる
                        if (auto select_result = db::select_revert(db, entity_name, rev_save_id, current_save_id)) {
                            reverted_attrs.emplace(entity_name, std::move(select_result.value()));
                        } else {
                            reverted_attrs.clear();
                            state = db::make_error_result(db::manager_error_type::select_revert_failed,
                                                          std::move(select_result.error()));
                            break;
                        }
                    }
                }

                if (state) {
                    for (auto const &entity_attrs_pair : reverted_attrs) {
                        auto const &entity_name = entity_attrs_pair.first;
                        auto const &entity_attrs = entity_attrs_pair.second;
                        auto const &rel_models = manager.model().relations(entity_name);

                        // アトリビュートのみのデータから関連のデータを加えてobject_dataを生成する
                        if (auto obj_datas_result =
                                db::make_entity_object_datas(db, entity_name, rel_models, entity_attrs)) {
                            reverted_datas.emplace(entity_name, std::move(obj_datas_result.value()));
                        } else {
                            reverted_attrs.clear();
                            reverted_datas.clear();
                            state = db::make_error_result(db::manager_error_type::make_object_datas_failed,
                                                          std::move(obj_datas_result.error()));
                            break;
                        }
                    }
                }

                if (state) {
                    // リバートしたセーブIDでinfoを更新する
                    if (auto update_result = db::update_current_save_id(db, db::value{rev_save_id})) {
                        ret_db_info = std::move(update_result.value());
                    } else {
                        state = db::manager_result_t{std::move(update_result.error())};
                    }
                }

                // トランザクション終了
                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                    reverted_datas.clear();
                    ret_db_info = db::null_info();
                }
            } else {
                state = db::make_error_result(db::manager_error_type::begin_transaction_failed,
                                              std::move(begin_result.error()));
            }

            // 結果を返す
            completion(std::move(state), std::move(reverted_datas), std::move(ret_db_info));
        };

        this->execute(execution, std::move(option));
    }

    // バックグラウンド処理を保留するカウントをあげる
    void suspend() {
        if (_suspend_count == 0) {
            _op_queue.suspend();
        }

        ++_suspend_count;
    }

    // バックグラウンド処理を保留するカウントを下げる。カウントが0になれば再開
    void resume() {
        if (_suspend_count == 0) {
            throw std::underflow_error("resume too much.");
        }

        --_suspend_count;

        if (_suspend_count == 0) {
            _op_queue.resume();
        }
    }
};

#pragma mark - manager

db::manager::manager(std::string const &db_path, db::model const &model, std::size_t const priority_count,
                     dispatch_queue_t const dispatch_queue)
    : base(std::make_unique<impl>(db_path, model, dispatch_queue, priority_count)) {
}

db::manager::manager(std::nullptr_t) : base(nullptr) {
}

void db::manager::suspend() {
    impl_ptr<impl>()->suspend();
}

void db::manager::resume() {
    impl_ptr<impl>()->resume();
}

bool db::manager::is_suspended() const {
    return impl_ptr<impl>()->_op_queue.is_suspended();
}

std::string const &db::manager::database_path() const {
    return impl_ptr<impl>()->_database.database_path();
}

db::database const &db::manager::database() const {
    return impl_ptr<impl>()->_database;
}

db::database &db::manager::database() {
    return impl_ptr<impl>()->_database;
}

db::model const &db::manager::model() const {
    return impl_ptr<impl>()->_model;
}

db::value const &db::manager::current_save_id() const {
    if (auto info = impl_ptr<impl>()->_db_info) {
        return info.current_save_id_value();
    }
    return db::null_value();
}

db::value const &db::manager::last_save_id() const {
    if (auto info = impl_ptr<impl>()->_db_info) {
        return info.last_save_id_value();
    }
    return db::null_value();
}

dispatch_queue_t db::manager::dispatch_queue() const {
    return impl_ptr<impl>()->_dispatch_queue;
}

db::object db::manager::insert_object(std::string const entity_name) {
    return impl_ptr<impl>()->insert_object(entity_name);
}

void db::manager::setup(db::manager::completion_f completion, operation_option_t option) {
    auto impl_completion =
        [completion = std::move(completion), manager = *this](db::manager_result_t && state, db::info && info) mutable {
        auto lambda =
            [manager, state = std::move(state), info = std::move(info), completion = std::move(completion)]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(info));
            }
            completion(std::move(state));
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_setup(std::move(impl_completion), std::move(option));
}

void db::manager::clear(db::manager::completion_f completion, operation_option_t option) {
    auto impl_completion =
        [completion = std::move(completion), manager = *this](db::manager_result_t && state, db::info && db_info) {
        auto lambda = [
            completion = std::move(completion), manager, state = std::move(state), db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                manager.impl_ptr<impl>()->clear_cached_objects();
            }
            completion(std::move(state));
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_clear(std::move(impl_completion), std::move(option));
}

void db::manager::purge(db::manager::completion_f completion, operation_option_t option) {
    auto impl_completion =
        [completion = std::move(completion), manager = *this](db::manager_result_t && state, db::info && db_info) {
        auto lambda = [
            completion = std::move(completion), manager, state = std::move(state), db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                manager.impl_ptr<impl>()->purge_cached_objects();
            }

            completion(std::move(state));
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_purge(std::move(impl_completion), std::move(option));
}

void db::manager::reset(db::manager::completion_f completion, operation_option_t option) {
    auto preparation = [manager = *this]() {
        return manager.impl_ptr<impl>()->changed_object_ids_for_reset();
    };

    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager_result_t && state, db::object_data_vector_map_t && fetched_datas) {
        auto lambda = [
            manager, completion = std::move(completion), state = std::move(state),
            fetched_datas = std::move(fetched_datas)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->load_and_cache_map_object_from_datas(fetched_datas, true);
                manager.impl_ptr<impl>()->erase_changed_objects(fetched_datas);
                manager.impl_ptr<impl>()->_inserted_objects.clear();
                completion(db::manager_result_t{nullptr});
            } else {
                completion(db::manager_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::execute(db::manager::execution_f &&execution, operation_option_t &&option) {
    impl_ptr<impl>()->execute(std::move(execution), std::move(option));
}

void db::manager::insert_objects(db::manager::insert_preparation_count_f preparation,
                                 db::manager::vector_completion_f completion, operation_option_t option) {
    // エンティティごとの数を指定してデータベースにオブジェクトを挿入する
    auto impl_preparation = [preparation = std::move(preparation)]() {
        auto counts = preparation();
        db::value_map_vector_map_t values{};

        for (auto &count_pair : counts) {
            values.emplace(count_pair.first, db::value_map_vector_t{count_pair.second});
        }

        return values;
    };

    this->insert_objects(std::move(impl_preparation), std::move(completion), std::move(option));
}

void db::manager::insert_objects(db::manager::insert_preparation_values_f preparation,
                                 db::manager::vector_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager_result_t && state, db::object_data_vector_map_t && inserted_datas, db::info && db_info) {
        auto lambda = [
            state = std::move(state), inserted_datas = std::move(inserted_datas), manager,
            completion = std::move(completion), db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects =
                    manager.impl_ptr<impl>()->load_and_cache_vector_object_from_datas(inserted_datas, false, false);
                completion(db::manager_vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_insert(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::fetch_objects(db::manager::fetch_preparation_option_f preparation,
                                db::manager::vector_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager_result_t && state, db::object_data_vector_map_t && fetched_datas) {
        auto lambda = [
            state = std::move(state), completion = std::move(completion), fetched_datas = std::move(fetched_datas),
            manager
        ]() mutable {
            if (state) {
                auto loaded_objects =
                    manager.impl_ptr<impl>()->load_and_cache_vector_object_from_datas(fetched_datas, false, false);
                completion(db::manager_vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::fetch_const_objects(db::manager::fetch_preparation_option_f preparation,
                                      db::manager::const_vector_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager_result_t && state, db::object_data_vector_map_t && fetched_datas) {
        auto lambda = [
            state = std::move(state), completion = std::move(completion), fetched_datas = std::move(fetched_datas),
            manager
        ]() mutable {
            if (state) {
                completion(
                    db::manager_const_vector_result_t{db::to_const_vector_objects(manager.model(), fetched_datas)});
            } else {
                completion(db::manager_const_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::fetch_objects(db::manager::fetch_preparation_ids_f preparation,
                                db::manager::map_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager_result_t && state, db::object_data_vector_map_t && fetched_datas) {
        auto lambda = [
            manager, completion = std::move(completion), state = std::move(state),
            fetched_datas = std::move(fetched_datas)
        ]() mutable {
            if (state) {
                auto loaded_objects =
                    manager.impl_ptr<impl>()->load_and_cache_map_object_from_datas(fetched_datas, false);
                completion(db::manager_map_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager_map_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::fetch_const_objects(db::manager::fetch_preparation_ids_f preparation,
                                      db::manager::const_map_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager_result_t && state, db::object_data_vector_map_t && fetched_datas) {
        auto lambda = [
            manager, completion = std::move(completion), state = std::move(state),
            fetched_datas = std::move(fetched_datas)
        ]() mutable {
            if (state) {
                completion(db::manager_const_map_result_t{db::to_const_map_objects(manager.model(), fetched_datas)});
            } else {
                completion(db::manager_const_map_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::save(db::manager::vector_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager_result_t && state, db::object_data_vector_map_t && saved_datas, db::info && db_info) {
        auto lambda = [
            manager, state = std::move(state), completion = std::move(completion), saved_datas = std::move(saved_datas),
            db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects =
                    manager.impl_ptr<impl>()->load_and_cache_vector_object_from_datas(saved_datas, false, true);
                manager.impl_ptr<impl>()->erase_changed_objects(saved_datas);
                completion(db::manager_vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_save(std::move(impl_completion), std::move(option));
}

void db::manager::revert(db::manager::revert_preparation_f preparation, db::manager::vector_completion_f completion,
                         operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager_result_t && state, db::object_data_vector_map_t && reverted_datas, db::info && db_info) {
        auto lambda = [
            manager, state = std::move(state), completion = std::move(completion),
            reverted_datas = std::move(reverted_datas), db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects =
                    manager.impl_ptr<impl>()->load_and_cache_vector_object_from_datas(reverted_datas, false, false);
                completion(db::manager_vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_revert(std::move(preparation), std::move(impl_completion), std::move(option));
}

db::object db::manager::cached_object(std::string const &entity_name, db::integer::type const object_id) const {
    return impl_ptr<impl>()->cached_object(entity_name, object_id);
}

bool db::manager::has_inserted_objects() const {
    for (auto const &entity_pair : impl_ptr<impl>()->_inserted_objects) {
        if (entity_pair.second.size() > 0) {
            return true;
        }
    }

    return false;
}

bool db::manager::has_changed_objects() const {
    for (auto const &entity_pair : impl_ptr<impl>()->_changed_objects) {
        if (entity_pair.second.size() > 0) {
            return true;
        }
    }

    return false;
}

std::size_t db::manager::inserted_object_count(std::string const &entity_name) const {
    if (impl_ptr<impl>()->_inserted_objects.count(entity_name) > 0) {
        return impl_ptr<impl>()->_inserted_objects.at(entity_name).size();
    }
    return 0;
}

std::size_t db::manager::changed_object_count(std::string const &entity_name) const {
    if (impl_ptr<impl>()->_changed_objects.count(entity_name) > 0) {
        return impl_ptr<impl>()->_changed_objects.at(entity_name).size();
    }
    return 0;
}

db::manager::subject_t const &db::manager::subject() const {
    return impl_ptr<impl>()->_subject;
}

db::manager::subject_t &db::manager::subject() {
    return impl_ptr<impl>()->_subject;
}

db::object_observable &db::manager::object_observable() {
    if (!this->_object_observable) {
        this->_object_observable = db::object_observable{impl_ptr<db::object_observable::impl>()};
    }
    return _object_observable;
}
