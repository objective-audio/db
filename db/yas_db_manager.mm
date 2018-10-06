//
//  yas_db_manager.cpp
//

#include "yas_db_manager.h"
#include "yas_chaining.h"
#include "yas_db_attribute.h"
#include "yas_db_database.h"
#include "yas_db_entity.h"
#include "yas_db_fetch_option.h"
#include "yas_db_index.h"
#include "yas_db_info.h"
#include "yas_db_manager_utils.h"
#include "yas_db_model.h"
#include "yas_db_object_utils.h"
#include "yas_db_relation.h"
#include "yas_db_select_option.h"
#include "yas_db_sql_utils.h"
#include "yas_db_utils.h"
#include "yas_each_index.h"
#include "yas_objc_macros.h"
#include "yas_operation.h"
#include "yas_result.h"
#include "yas_stl_utils.h"
#include "yas_unless.h"

using namespace yas;

#pragma mark - impl

struct db::manager::impl : base::impl, public object_observable::impl {
    db::database _database;
    db::model _model;
    operation_queue _op_queue;
    std::size_t _suspend_count = 0;
    db::weak_pool<db::object_id, db::object> _cached_objects;
    db::tmp_object_map_map_t _created_objects;
    db::object_map_map_t _changed_objects;
    chaining::holder<db::info> _db_info = db::null_info();
    chaining::notifier<db::object> _db_object_notifier;
    dispatch_queue_t _dispatch_queue;

    impl(std::string const &path, db::model const &model, dispatch_queue_t const dispatch_queue,
         std::size_t const priority_count)
        : _database(path), _model(model), _dispatch_queue(dispatch_queue), _op_queue(priority_count) {
        yas_dispatch_queue_retain(dispatch_queue);
    }

    ~impl() {
        yas_dispatch_queue_release(_dispatch_queue);
    }

    // データベースに保存せず仮にオブジェクトを生成する
    // この時点ではobject_idやsave_idは振られていない
    db::object create_temporary_object(db::manager &manager, std::string const entity_name) {
        db::object object = manager.make_object(entity_name);

        object.manageable().load_insertion_data();

        if (this->_created_objects.count(entity_name) == 0) {
            this->_created_objects.insert(std::make_pair(entity_name, db::tmp_object_map_t{}));
        }

        // この時点でobject_idはtemporary
        this->_created_objects.at(entity_name).emplace(object.object_id().temporary(), object);

        return object;
    }

    db::object load_and_cache_object(std::string const &entity_name, db::object_data const &data, bool const force,
                                     bool const is_save) {
        if (!data.object_id) {
            throw std::invalid_argument("object_id not found.");
        }

        auto object = db::null_object();

        if (is_save && this->_created_objects.count(entity_name) > 0) {
            // セーブ時で仮に挿入されたオブジェクトがある場合にオブジェクトを取得
            auto &entity_objects = this->_created_objects.at(entity_name);
            if (entity_objects.size() > 0) {
                auto const &temporary_id = data.object_id.temporary();
                if (entity_objects.count(temporary_id) > 0) {
                    object = entity_objects.at(temporary_id);
                    entity_objects.erase(temporary_id);

                    db::object_id obj_id = object.object_id();
                    obj_id.set_stable(data.object_id.stable_value());
                    this->_cached_objects.set(entity_name, obj_id, object);

                    if (entity_objects.size() == 0) {
                        this->_created_objects.erase(entity_name);
                    }
                }
            }
        }

        if (!object) {
            // 挿入でなければobjectはnullなので、キャッシュに追加または取得する
            auto manager = cast<db::manager>();
            object = this->_cached_objects.get_or_create(
                entity_name, data.object_id, [&manager, &entity_name]() { return manager.make_object(entity_name); });
        }

        // オブジェクトにデータをロード
        object.manageable().load_data(data, force);

        return object;
    }

    // 複数のエンティティのデータをロードしてキャッシュする
    // ロードされたオブエジェクトはエンティティごとに順番がある状態で返される
    db::object_vector_map_t load_and_cache_object_vector(db::object_data_vector_map_t const &datas, bool const force,
                                                         bool const is_save) {
        db::object_vector_map_t loaded_objects;
        for (auto const &entity_pair : datas) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_datas = entity_pair.second;

            db::object_vector_t objects;
            objects.reserve(entity_datas.size());

            for (db::object_data const &data : entity_datas) {
                auto object = this->load_and_cache_object(entity_name, data, force, is_save);
                objects.emplace_back(std::move(object));
            }

            loaded_objects.emplace(entity_name, std::move(objects));
        }
        return loaded_objects;
    }

    // 複数のエンティティのデータをロードしてキャッシュする
    // ロードされたオブジェクトはエンティティごとにobject_idをキーとしたmapで返される
    db::object_map_map_t load_and_cache_object_map(db::object_data_vector_map_t const &datas, bool const force,
                                                   bool const is_save) {
        db::object_map_map_t loaded_objects;
        for (auto const &entity_pair : datas) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_datas = entity_pair.second;

            db::object_map_t objects;
            objects.reserve(entity_datas.size());

            for (auto const &data : entity_datas) {
                auto object = this->load_and_cache_object(entity_name, data, force, is_save);
                objects.emplace(object.object_id().stable(), std::move(object));
            }

            loaded_objects.emplace(entity_name, std::move(objects));
        }
        return loaded_objects;
    }

    // キャッシュされている全てのオブジェクトをクリアする
    void clear_cached_objects() {
        this->_cached_objects.perform(
            [](std::string const &, db::object_id const &, auto &object) { object.manageable().clear_data(); });
        this->_cached_objects.clear();
    }

    // キャッシュされている全てのオブジェクトをパージする（save_idを全て1にする）
    // データベースのパージが成功した時に呼ばれる
    void purge_cached_objects() {
        // キャッシュされたオブジェクトのセーブIDを全て1にする
        db::value one_value{db::integer::type{1}};
        this->_cached_objects.perform(
            [one_value = std::move(one_value)](std::string const &, db::object_id const &, auto &object) {
                object.manageable().load_save_id(one_value);
            });
    }

    // データベース情報を置き換える
    void set_db_info(db::info &&info) {
        this->_db_info.set_value(std::move(info));
    }

    // データベースに保存するために、全てのエンティティで変更のあったオブジェクトのobject_dataを取得する
    db::object_data_vector_map_t changed_datas_for_save() {
        db::object_data_vector_map_t changed_datas;
        db::object_id_pool_t obj_id_pool;

        for (auto const &entity_pair : this->_model.entities()) {
            // エンティティごとの処理
            auto const &entity_name = entity_pair.first;

            // 仮に挿入されたオブジェクトの数
            std::size_t const inserted_count =
                this->_created_objects.count(entity_name) ? this->_created_objects.at(entity_name).size() : 0;
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
                auto const &entity_objects = this->_created_objects.at(entity_name);

                for (auto const &pair : entity_objects) {
                    auto const &object = pair.second;
                    auto data = object.save_data(obj_id_pool);
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
                    auto data = object.save_data(obj_id_pool);
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
                entity_ids.insert(object.object_id().stable());
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
                        erase_if_exists(changed_entity_objects, obj_data.object_id.stable());
                    }

                    if (changed_entity_objects.size() == 0) {
                        this->_changed_objects.erase(entity_name);
                    }
                }
            }
        }
    }

    db::object _inserted_object(std::string const &entity_name, std::string const &tmp_obj_id) {
        if (this->_created_objects.count(entity_name) > 0) {
            auto const &entity_objects = this->_created_objects.at(entity_name);
            if (entity_objects.count(tmp_obj_id) > 0) {
                return entity_objects.at(tmp_obj_id);
            }
        }
        return db::null_object();
    }

    // キャッシュされた単独のオブジェクトをエンティティ名とオブジェクトIDを指定して取得する
    db::object cached_or_created_object(std::string const &entity_name, db::object_id const &object_id) {
        if (object_id.is_temporary()) {
            return this->_inserted_object(entity_name, object_id.temporary());
        } else {
            return this->_cached_objects.get(entity_name, object_id);
        }
    }

    // オブジェクトに変更があった時の処理
    void _object_did_change(db::object const &object) {
        auto const &entity_name = object.entity_name();

        if (object.status() == db::object_status::created) {
            // 仮に挿入された状態の場合
            if (this->_created_objects.count(entity_name) > 0 && object.is_removed()) {
                // オブジェクトが削除されていたら、_created_objectsからも削除
                this->_created_objects.at(entity_name).erase(object.object_id().temporary());
            }
        } else {
            // 挿入されたのではない場合
            if (this->_changed_objects.count(entity_name) == 0) {
                // _changed_objectsにエンティティのmapがなければ生成する
                this->_changed_objects.insert(std::make_pair(entity_name, db::object_map_t{}));
            }

            // _changed_objectsにオブジェクトを追加
            auto const &obj_id = object.object_id().stable();
            if (this->_changed_objects.at(entity_name).count(obj_id) == 0) {
                this->_changed_objects.at(entity_name).emplace(obj_id, object);
            }
        }

        if (object.is_removed()) {
            // オブジェクトが削除されていたら逆関連も削除する
            for (auto const &entity_pair : this->_model.entity(entity_name).inverse_relation_names) {
                auto const &inv_entity_name = entity_pair.first;
                auto const &inv_rel_names = entity_pair.second;

                this->_cached_objects.perform_entity(
                    inv_entity_name,
                    [&inv_rel_names, &object](std::string const &, db::object_id const &, db::object &inv_rel_obj) {
                        for (auto const &inv_rel_name : inv_rel_names) {
                            inv_rel_obj.remove_relation_id(inv_rel_name, object.object_id());
                        }
                    });
            }
        }

        // オブジェクトが変更された通知を送信
        this->_db_object_notifier.notify(object);
    }

    // オブジェクトが解放された時の処理
    void _object_did_erase(std::string const &entity_name, db::object_id const &object_id) {
        // キャッシュからオブジェクトを削除する
        // キャッシュにはweakで持っている
        this->_cached_objects.erase(entity_name, object_id);
    }

    // バックグラウンドでデータベースの処理をする
    void execute(db::cancellation_f &&cancellation, db::execution_f &&execution) {
        auto op_lambda = [cancellation = std::move(cancellation), execution = std::move(execution),
                          manager = cast<manager>()](operation const &op) mutable {
            if (!op.is_canceled() && !cancellation()) {
                auto &db = manager.impl_ptr<impl>()->_database;
                db.open();
                execution(op);
                db.close();
            }
        };

        this->_op_queue.push_back(operation{std::move(op_lambda)});
    }

    // バックグラウンドでデータベースからオブジェクトデータを取得する。条件はselect_optionで指定。単独のエンティティのみ
    void execute_fetch_object_datas(
        db::cancellation_f &&cancellation, db::fetch_option_preparation_f &&preparation,
        std::function<void(db::manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas)> &&completion) {
        auto execution = [preparation = std::move(preparation), completion = std::move(completion),
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

        this->execute(std::move(cancellation), std::move(execution));
    }

    // バックグラウンドでデータベースからオブジェクトデータを取得する。条件はobject_idで指定。単独のエンティティのみ
    void execute_fetch_object_datas(
        db::cancellation_f &&cancellation, fetch_ids_preparation_f &&ids_preparation,
        std::function<void(db::manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas)> &&completion) {
        db::fetch_option_preparation_f opt_preparation = [ids_preparation = std::move(ids_preparation)]() {
            return db::to_fetch_option(ids_preparation());
        };

        this->execute_fetch_object_datas(std::move(cancellation), std::move(opt_preparation), std::move(completion));
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
    if (auto info = impl_ptr<impl>()->_db_info.value()) {
        return info.current_save_id_value();
    }
    return db::null_value();
}

db::value const &db::manager::last_save_id() const {
    if (auto info = impl_ptr<impl>()->_db_info.value()) {
        return info.last_save_id_value();
    }
    return db::null_value();
}

dispatch_queue_t db::manager::dispatch_queue() const {
    return impl_ptr<impl>()->_dispatch_queue;
}

db::object db::manager::create_object(std::string const entity_name) {
    return impl_ptr<impl>()->create_temporary_object(*this, entity_name);
}

void db::manager::setup(db::completion_f completion) {
    auto execution = [completion = std::move(completion), manager = *this](operation const &op) mutable {
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
            if (auto select_result = db::fetch_info(db)) {
                info = std::move(select_result.value());
            } else {
                state = db::manager_result_t{select_result.error()};
            }
        }

        auto completion_on_main = [manager, state = std::move(state), info = std::move(info),
                                   completion = std::move(completion)]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(info));
            }
            completion(std::move(state));
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    this->execute(db::no_cancellation, std::move(execution));
}

void db::manager::clear(db::cancellation_f cancellation, db::completion_f completion) {
    auto execution = [completion = std::move(completion), manager = *this](operation const &op) mutable {
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
                if (auto update_result = db::update_info(db, zero_value, zero_value)) {
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

        auto completion_on_main = [completion = std::move(completion), manager, state = std::move(state),
                                   db_info = std::move(db_info)]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                manager.impl_ptr<impl>()->clear_cached_objects();
            }
            completion(std::move(state));
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    this->execute(std::move(cancellation), std::move(execution));
}

void db::manager::purge(db::cancellation_f cancellation, db::completion_f completion) {
    auto execution = [completion = std::move(completion), manager = *this](operation const &op) mutable {
        auto &db = manager.database();
        auto const &model = manager.model();

        db::info db_info = db::null_info();
        db::manager_result_t state{nullptr};

        // トランザクション開始
        if (auto begin_result = db::begin_transaction(db)) {
            if (auto purge_result = db::purge_db(db, model)) {
                // infoをクリア。セーブIDを1にする
                db::value const one_value = db::value{db::integer::type{1}};
                if (auto update_result = db::update_info(db, one_value, one_value)) {
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

        auto completion_on_main = [completion = std::move(completion), manager, state = std::move(state),
                                   db_info = std::move(db_info)]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                manager.impl_ptr<impl>()->purge_cached_objects();
            }

            completion(std::move(state));
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    this->execute(std::move(cancellation), std::move(execution));
}

void db::manager::reset(db::cancellation_f cancellation, db::completion_f completion) {
    auto preparation = [manager = *this]() { return manager.impl_ptr<impl>()->changed_object_ids_for_reset(); };

    auto impl_completion = [completion = std::move(completion), manager = *this](
                               db::manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas) {
        auto completion_on_main = [manager, completion = std::move(completion), state = std::move(state),
                                   fetched_datas = std::move(fetched_datas)]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->load_and_cache_object_map(fetched_datas, true, false);
                manager.impl_ptr<impl>()->erase_changed_objects(fetched_datas);
                manager.impl_ptr<impl>()->_created_objects.clear();
                completion(db::manager_result_t{nullptr});
            } else {
                completion(db::manager_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(cancellation), std::move(preparation),
                                                 std::move(impl_completion));
}

void db::manager::execute(db::cancellation_f cancellation, db::execution_f &&execution) {
    impl_ptr<impl>()->execute(std::move(cancellation), std::move(execution));
}

void db::manager::insert_objects(db::cancellation_f cancellation, db::insert_count_preparation_f preparation,
                                 db::vector_completion_f completion) {
    // エンティティごとの数を指定してデータベースにオブジェクトを挿入する
    auto impl_preparation = [preparation = std::move(preparation)]() {
        auto counts = preparation();
        db::value_map_vector_map_t values{};

        for (auto &count_pair : counts) {
            values.emplace(count_pair.first, db::value_map_vector_t{count_pair.second});
        }

        return values;
    };

    this->insert_objects(std::move(cancellation), std::move(impl_preparation), std::move(completion));
}

void db::manager::insert_objects(db::cancellation_f cancellation, db::insert_values_preparation_f preparation,
                                 db::vector_completion_f completion) {
    auto execution = [preparation = std::move(preparation), completion = std::move(completion),
                      manager = *this](operation const &op) mutable {
        // 挿入するオブジェクトのデータをメインスレッドで準備する
        db::value_map_vector_map_t values;

        auto preparation_on_main = [&values, &preparation]() { values = preparation(); };
        dispatch_sync(manager.dispatch_queue(), std::move(preparation_on_main));

        auto &db = manager.database();
        auto const &model = manager.model();

        db::info ret_db_info = db::null_info();
        db::object_data_vector_map_t inserted_datas;

        db::manager_result_t state{nullptr};

        if (auto begin_result = db::begin_transaction(db)) {
            // トランザクション開始

            // DB情報を取得する
            db::info info = db::null_info();
            if (auto info_result = db::fetch_info(db)) {
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
                if (auto update_result = db::update_info(db, next_save_id, next_save_id)) {
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

        auto completion_on_main = [state = std::move(state), inserted_datas = std::move(inserted_datas), manager,
                                   completion = std::move(completion), db_info = std::move(ret_db_info)]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects =
                    manager.impl_ptr<impl>()->load_and_cache_object_vector(inserted_datas, false, false);
                completion(db::manager_vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    this->execute(std::move(cancellation), std::move(execution));
}

void db::manager::fetch_objects(db::cancellation_f cancellation, db::fetch_option_preparation_f preparation,
                                db::vector_completion_f completion) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
                               db::manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas) {
        auto completion_on_main = [state = std::move(state), completion = std::move(completion),
                                   fetched_datas = std::move(fetched_datas), manager]() mutable {
            if (state) {
                auto loaded_objects =
                    manager.impl_ptr<impl>()->load_and_cache_object_vector(fetched_datas, false, false);
                completion(db::manager_vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(cancellation), std::move(preparation),
                                                 std::move(impl_completion));
}

void db::manager::fetch_const_objects(db::cancellation_f cancellation, db::fetch_option_preparation_f preparation,
                                      db::const_vector_completion_f completion) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
                               db::manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas) {
        auto completion_on_main = [state = std::move(state), completion = std::move(completion),
                                   fetched_datas = std::move(fetched_datas), manager]() mutable {
            if (state) {
                completion(
                    db::manager_const_vector_result_t{db::to_const_vector_objects(manager.model(), fetched_datas)});
            } else {
                completion(db::manager_const_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(cancellation), std::move(preparation),
                                                 std::move(impl_completion));
}

void db::manager::fetch_objects(db::cancellation_f cancellation, db::fetch_ids_preparation_f preparation,
                                db::map_completion_f completion) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
                               db::manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas) {
        auto completion_on_main = [manager, completion = std::move(completion), state = std::move(state),
                                   fetched_datas = std::move(fetched_datas)]() mutable {
            if (state) {
                auto loaded_objects = manager.impl_ptr<impl>()->load_and_cache_object_map(fetched_datas, false, false);
                completion(db::manager_map_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager_map_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(cancellation), std::move(preparation),
                                                 std::move(impl_completion));
}

void db::manager::fetch_const_objects(db::cancellation_f cancellation, db::fetch_ids_preparation_f preparation,
                                      db::const_map_completion_f completion) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
                               db::manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas) {
        auto completion_on_main = [manager, completion = std::move(completion), state = std::move(state),
                                   fetched_datas = std::move(fetched_datas)]() mutable {
            if (state) {
                completion(db::manager_const_map_result_t{db::to_const_map_objects(manager.model(), fetched_datas)});
            } else {
                completion(db::manager_const_map_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(cancellation), std::move(preparation),
                                                 std::move(impl_completion));
}

void db::manager::save(db::cancellation_f cancellation, db::map_completion_f completion) {
    auto execution = [completion = std::move(completion), manager = *this](operation const &) mutable {
        db::object_data_vector_map_t changed_datas;
        // 変更のあったデータをメインスレッドで取得する
        auto manager_impl = manager.impl_ptr<impl>();

        auto get_changed_on_main = [&manager_impl, &changed_datas]() {
            changed_datas = manager_impl->changed_datas_for_save();
        };
        dispatch_sync(manager.dispatch_queue(), std::move(get_changed_on_main));

        auto &db = manager.database();
        auto const &model = manager.model();

        db::info db_info = db::null_info();
        db::object_data_vector_map_t saved_datas;

        db::manager_result_t state{nullptr};

        // データベースからセーブIDを取得する
        if (auto select_result = db::fetch_info(db)) {
            db_info = std::move(select_result.value());
        } else {
            state = db::manager_result_t{std::move(select_result.error())};
        }

        if (state && changed_datas.size() > 0) {
            // トランザクション開始
            if (auto begin_result = db::begin_transaction(db)) {
                // 変更のあったデータをデータベースに保存する
                if (auto save_result = db::save(db, model, db_info, changed_datas)) {
                    saved_datas = std::move(save_result.value());
                } else {
                    state = db::manager_result_t{std::move(save_result.error())};
                }

                if (auto ul = unless(db::remove_relations_at_save(db, model, db_info, changed_datas))) {
                    state = std::move(ul.value);
                }

                if (state) {
                    // infoの更新
                    auto const &next_save_id = db_info.next_save_id_value();
                    if (auto update_result = db::update_info(db, next_save_id, next_save_id)) {
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

        auto completion_on_main = [manager, state = std::move(state), completion = std::move(completion),
                                   saved_datas = std::move(saved_datas), db_info = std::move(db_info)]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects = manager.impl_ptr<impl>()->load_and_cache_object_map(saved_datas, false, true);
                manager.impl_ptr<impl>()->erase_changed_objects(saved_datas);
                completion(db::manager_map_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager_map_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    this->execute(std::move(cancellation), std::move(execution));
}

void db::manager::revert(db::cancellation_f cancellation, db::revert_preparation_f preparation,
                         db::vector_completion_f completion) {
    auto execution = [preparation = std::move(preparation), completion = std::move(completion),
                      manager = *this](operation const &) mutable {
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

            if (auto select_result = db::fetch_info(db)) {
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
                    if (auto select_result = db::select_for_revert(db, entity_name, rev_save_id, current_save_id)) {
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

        auto completion_on_main = [manager, state = std::move(state), completion = std::move(completion),
                                   reverted_datas = std::move(reverted_datas),
                                   db_info = std::move(ret_db_info)]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects =
                    manager.impl_ptr<impl>()->load_and_cache_object_vector(reverted_datas, false, false);
                completion(db::manager_vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(completion_on_main));
    };

    this->execute(std::move(cancellation), std::move(execution));
}

db::object db::manager::cached_or_created_object(std::string const &entity_name, db::object_id const &object_id) const {
    return impl_ptr<impl>()->cached_or_created_object(entity_name, object_id);
}

bool db::manager::has_created_objects() const {
    for (auto const &entity_pair : impl_ptr<impl>()->_created_objects) {
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

std::size_t db::manager::created_object_count(std::string const &entity_name) const {
    if (impl_ptr<impl>()->_created_objects.count(entity_name) > 0) {
        return impl_ptr<impl>()->_created_objects.at(entity_name).size();
    }
    return 0;
}

std::size_t db::manager::changed_object_count(std::string const &entity_name) const {
    if (impl_ptr<impl>()->_changed_objects.count(entity_name) > 0) {
        return impl_ptr<impl>()->_changed_objects.at(entity_name).size();
    }
    return 0;
}

chaining::chain_syncable_t<db::info> db::manager::chain_db_info() const {
    return impl_ptr<impl>()->_db_info.chain();
}

chaining::chain_unsyncable_t<db::object> db::manager::chain_db_object() const {
    return impl_ptr<impl>()->_db_object_notifier.chain();
}

db::object_observable &db::manager::object_observable() {
    if (!this->_object_observable) {
        this->_object_observable = db::object_observable{impl_ptr<db::object_observable::impl>()};
    }
    return _object_observable;
}

db::object db::manager::make_object(std::string const &entity_name) {
    db::object obj{*this, this->model().entity(entity_name)};
#warning
    return obj;
}
