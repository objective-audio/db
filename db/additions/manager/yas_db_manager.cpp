//
//  yas_db_manager.cpp
//

#include "yas_db_manager.h"

#include <cpp_utils/yas_thread.h>
#include <cpp_utils/yas_unless.h>

#include "yas_db_attribute.h"
#include "yas_db_database.h"
#include "yas_db_index.h"
#include "yas_db_info.h"
#include "yas_db_manager_utils.h"
#include "yas_db_relation.h"
#include "yas_db_sql_utils.h"
#include "yas_db_utils.h"

using namespace yas;
using namespace yas::db;

manager::manager(std::string const &db_path, db::model const &model, std::size_t const priority_count)
    : _database(database::make_shared(db_path)),
      _model(model),
      _task_queue(priority_count),
      _db_info(observing::value::holder<db::info_opt>::make_shared(std::nullopt)),
      _db_object_notifier(observing::notifier<db::object_ptr>::make_shared()) {
}

// バックグラウンド処理を保留するカウントをあげる
void manager::suspend() {
    if (this->_suspend_count == 0) {
        this->_task_queue.suspend();
    }

    ++this->_suspend_count;
}

// バックグラウンド処理を保留するカウントを下げる。カウントが0になれば再開
void manager::resume() {
    if (this->_suspend_count == 0) {
        throw std::underflow_error("resume too much.");
    }

    --this->_suspend_count;

    if (this->_suspend_count == 0) {
        this->_task_queue.resume();
    }
}

bool manager::is_suspended() const {
    return this->_task_queue.is_suspended();
}

std::string const &manager::database_path() const {
    return this->_database->database_path();
}

db::database_ptr const &manager::database() const {
    return this->_database;
}

db::model const &manager::model() const {
    return this->_model;
}

db::value const &manager::current_save_id() const {
    if (auto const &info = this->_db_info->value()) {
        return info->current_save_id_value();
    }
    return db::null_value();
}

db::value const &manager::last_save_id() const {
    if (auto const &info = this->_db_info->value()) {
        return info->last_save_id_value();
    }
    return db::null_value();
}

// データベースに保存せず仮にオブジェクトを生成する
// この時点ではobject_idやsave_idは振られていない
db::object_ptr manager::create_object(std::string const entity_name) {
    auto manager = this->_weak_manager.lock();

    db::object_ptr object = manager->make_object(entity_name);

    manageable_object::cast(object)->load_insertion_data();

    if (this->_created_objects.count(entity_name) == 0) {
        this->_created_objects.insert(std::make_pair(entity_name, db::tmp_object_map_t{}));
    }

    // この時点でobject_idはtemporary
    this->_created_objects.at(entity_name).emplace(object->object_id().temporary(), object);

    return object;
}

void manager::setup(db::completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto execution = [completion = std::move(completion), manager](task const &) mutable {
        db::database_ptr const &db = manager->database();
        db::model const &model = manager->model();

        manager_result_t state{nullptr};

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
            state =
                db::make_error_result(manager_error_type::begin_transaction_failed, std::move(begin_result.error()));
        }

        db::info_opt info = std::nullopt;

        if (state) {
            if (auto select_result = db::fetch_info(db)) {
                info = std::move(select_result.value());
            } else {
                state = manager_result_t{select_result.error()};
            }
        }

        auto completion_on_main = [manager, state = std::move(state), info = std::move(info),
                                   completion = std::move(completion)]() mutable {
            if (state) {
                manager->_set_db_info(std::move(info));
            }
            completion(std::move(state));
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->execute(db::no_cancellation, std::move(execution));
}

void manager::clear(db::cancellation_f cancellation, db::completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto execution = [completion = std::move(completion), manager](task const &) mutable {
        auto &db = manager->database();
        auto const &model = manager->model();

        db::info_opt db_info = std::nullopt;
        manager_result_t state{nullptr};

        // トランザクション開始
        if (auto begin_result = db::begin_transaction(db)) {
            // DBをクリアする
            if (auto clear_result = db::clear_db(db, model)) {
                // infoをクリア。セーブIDを0にする
                db::value const zero_value{db::integer::type{0}};
                if (auto update_result = db::update_info(db, zero_value, zero_value)) {
                    db_info = std::move(update_result.value());
                } else {
                    state = manager_result_t{std::move(update_result.error())};
                }
            } else {
                state = std::move(clear_result);
            }

            // トランザクション終了
            if (state) {
                db::commit(db);
            } else {
                db::rollback(db);
                db_info = std::nullopt;
            }
        } else {
            state =
                db::make_error_result(manager_error_type::begin_transaction_failed, std::move(begin_result.error()));
        }

        auto completion_on_main = [completion = std::move(completion), manager, state = std::move(state),
                                   db_info = std::move(db_info)]() mutable {
            if (state) {
                manager->_set_db_info(std::move(db_info));
                manager->_clear_cached_objects();
            }
            completion(std::move(state));
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->execute(std::move(cancellation), std::move(execution));
}

void manager::purge(db::cancellation_f cancellation, db::completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto execution = [completion = std::move(completion), manager](task const &) mutable {
        auto &db = manager->database();
        auto const &model = manager->model();

        db::info_opt db_info = std::nullopt;
        manager_result_t state{nullptr};

        // トランザクション開始
        if (auto begin_result = db::begin_transaction(db)) {
            if (auto purge_result = db::purge_db(db, model)) {
                // infoをクリア。セーブIDを1にする
                db::value const one_value = db::value{db::integer::type{1}};
                if (auto update_result = db::update_info(db, one_value, one_value)) {
                    db_info = std::move(update_result.value());
                } else {
                    state = manager_result_t{std::move(update_result.error())};
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
            state =
                db::make_error_result(manager_error_type::begin_transaction_failed, std::move(begin_result.error()));
        }

        if (state) {
            // バキュームする（バキュームはトランザクション中はできない）
            if (auto ul = unless(db->execute_update(db::vacuum_sql()))) {
                state = db::make_error_result(manager_error_type::vacuum_failed, std::move(ul.value.error()));
            }
        }

        auto completion_on_main = [completion = std::move(completion), manager, state = std::move(state),
                                   db_info = std::move(db_info)]() mutable {
            if (state) {
                manager->_set_db_info(std::move(db_info));
                manager->_purge_cached_objects();
            }

            completion(std::move(state));
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->execute(std::move(cancellation), std::move(execution));
}

void manager::reset(db::cancellation_f cancellation, db::completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto preparation = [manager]() { return manager->_changed_object_ids_for_reset(); };

    auto impl_completion = [completion = std::move(completion), manager](manager_result_t &&state,
                                                                         db::object_data_vector_map_t &&fetched_datas) {
        auto completion_on_main = [manager, completion = std::move(completion), state = std::move(state),
                                   fetched_datas = std::move(fetched_datas)]() mutable {
            if (state) {
                manager->_load_and_cache_object_map(fetched_datas, true, false);
                manager->_erase_changed_objects(fetched_datas);
                manager->_created_objects.clear();
                completion(manager_result_t{nullptr});
            } else {
                completion(manager_result_t{std::move(state.error())});
            }
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->_execute_fetch_object_datas(std::move(cancellation), std::move(preparation), std::move(impl_completion));
}

void manager::execute(db::cancellation_f cancellation, db::execution_f &&execution) {
    this->_execute(std::move(cancellation), std::move(execution));
}

void manager::insert_objects(db::cancellation_f cancellation, db::insert_count_preparation_f preparation,
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

void manager::insert_objects(db::cancellation_f cancellation, db::insert_values_preparation_f preparation,
                             db::vector_completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto execution = [preparation = std::move(preparation), completion = std::move(completion),
                      manager](task const &) mutable {
        // 挿入するオブジェクトのデータをメインスレッドで準備する
        db::value_map_vector_map_t values;

        auto preparation_on_main = [&values, &preparation] { values = preparation(); };
        thread::perform_sync_on_main(std::move(preparation_on_main));

        auto &db = manager->database();
        auto const &model = manager->model();

        db::info_opt ret_db_info = std::nullopt;
        db::object_data_vector_map_t inserted_datas;

        manager_result_t state{nullptr};

        if (auto begin_result = db::begin_transaction(db)) {
            // トランザクション開始

            // DB情報を取得する
            db::info_opt info = std::nullopt;
            if (auto info_result = db::fetch_info(db)) {
                info = std::move(info_result.value());
            } else {
                state = manager_result_t{std::move(info_result.error())};
            }

            if (state) {
                // DB上に新規にデータを挿入する
                if (auto insert_result = db::insert(db, model, *info, std::move(values))) {
                    inserted_datas = std::move(insert_result.value());
                } else {
                    state = manager_result_t{std::move(insert_result.error())};
                }
            }

            if (state) {
                // DB情報を更新する
                auto const next_save_id = info->next_save_id_value();
                if (auto update_result = db::update_info(db, next_save_id, next_save_id)) {
                    ret_db_info = std::move(update_result.value());
                } else {
                    state = manager_result_t{std::move(update_result.error())};
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
            state =
                db::make_error_result(manager_error_type::begin_transaction_failed, std::move(begin_result.error()));
        }

        auto completion_on_main = [state = std::move(state), inserted_datas = std::move(inserted_datas), manager,
                                   completion = std::move(completion), db_info = std::move(ret_db_info)]() mutable {
            if (state) {
                manager->_set_db_info(std::move(db_info));
                auto loaded_objects = manager->_load_and_cache_object_vector(inserted_datas, false, false);
                completion(manager_vector_result_t{std::move(loaded_objects)});
            } else {
                completion(manager_vector_result_t{std::move(state.error())});
            }
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->execute(std::move(cancellation), std::move(execution));
}

void manager::fetch_objects(db::cancellation_f cancellation, db::fetch_option_preparation_f preparation,
                            db::vector_completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto impl_completion = [completion = std::move(completion), manager](manager_result_t &&state,
                                                                         db::object_data_vector_map_t &&fetched_datas) {
        auto completion_on_main = [state = std::move(state), completion = std::move(completion),
                                   fetched_datas = std::move(fetched_datas), manager]() mutable {
            if (state) {
                auto loaded_objects = manager->_load_and_cache_object_vector(fetched_datas, false, false);
                completion(manager_vector_result_t{std::move(loaded_objects)});
            } else {
                completion(manager_vector_result_t{std::move(state.error())});
            }
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->_execute_fetch_object_datas(std::move(cancellation), std::move(preparation), std::move(impl_completion));
}

void manager::fetch_const_objects(db::cancellation_f cancellation, db::fetch_option_preparation_f preparation,
                                  db::const_vector_completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto impl_completion = [completion = std::move(completion), manager](manager_result_t &&state,
                                                                         db::object_data_vector_map_t &&fetched_datas) {
        auto completion_on_main = [state = std::move(state), completion = std::move(completion),
                                   fetched_datas = std::move(fetched_datas), manager]() mutable {
            if (state) {
                completion(manager_const_vector_result_t{db::to_const_vector_objects(manager->model(), fetched_datas)});
            } else {
                completion(manager_const_vector_result_t{std::move(state.error())});
            }
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->_execute_fetch_object_datas(std::move(cancellation), std::move(preparation), std::move(impl_completion));
}

void manager::fetch_objects(db::cancellation_f cancellation, db::fetch_ids_preparation_f preparation,
                            db::map_completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto impl_completion = [completion = std::move(completion), manager](manager_result_t &&state,
                                                                         db::object_data_vector_map_t &&fetched_datas) {
        auto completion_on_main = [manager, completion = std::move(completion), state = std::move(state),
                                   fetched_datas = std::move(fetched_datas)]() mutable {
            if (state) {
                auto loaded_objects = manager->_load_and_cache_object_map(fetched_datas, false, false);
                completion(manager_map_result_t{std::move(loaded_objects)});
            } else {
                completion(manager_map_result_t{std::move(state.error())});
            }
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->_execute_fetch_object_datas(std::move(cancellation), std::move(preparation), std::move(impl_completion));
}

void manager::fetch_const_objects(db::cancellation_f cancellation, db::fetch_ids_preparation_f preparation,
                                  db::const_map_completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto impl_completion = [completion = std::move(completion), manager](manager_result_t &&state,
                                                                         db::object_data_vector_map_t &&fetched_datas) {
        auto completion_on_main = [manager, completion = std::move(completion), state = std::move(state),
                                   fetched_datas = std::move(fetched_datas)]() mutable {
            if (state) {
                completion(manager_const_map_result_t{db::to_const_map_objects(manager->model(), fetched_datas)});
            } else {
                completion(manager_const_map_result_t{std::move(state.error())});
            }
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->_execute_fetch_object_datas(std::move(cancellation), std::move(preparation), std::move(impl_completion));
}

void manager::save(db::cancellation_f cancellation, db::map_completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto execution = [completion = std::move(completion), manager](task const &) mutable {
        db::object_data_vector_map_t changed_datas;
        // 変更のあったデータをメインスレッドで取得する
        auto get_changed_on_main = [&manager, &changed_datas]() { changed_datas = manager->_changed_datas_for_save(); };
        thread::perform_sync_on_main(std::move(get_changed_on_main));

        auto &db = manager->database();
        auto const &model = manager->model();

        db::info_opt db_info = std::nullopt;
        db::object_data_vector_map_t saved_datas;

        manager_result_t state{nullptr};

        // データベースからセーブIDを取得する
        if (auto select_result = db::fetch_info(db)) {
            db_info = std::move(select_result.value());
        } else {
            state = manager_result_t{std::move(select_result.error())};
        }

        if (state && changed_datas.size() > 0) {
            // トランザクション開始
            if (auto begin_result = db::begin_transaction(db)) {
                // 変更のあったデータをデータベースに保存する
                if (auto save_result = db::save(db, model, *db_info, changed_datas)) {
                    saved_datas = std::move(save_result.value());
                } else {
                    state = manager_result_t{std::move(save_result.error())};
                }

                if (auto ul = unless(db::remove_relations_at_save(db, model, *db_info, changed_datas))) {
                    state = std::move(ul.value);
                }

                if (state) {
                    // infoの更新
                    auto const &next_save_id = db_info->next_save_id_value();
                    if (auto update_result = db::update_info(db, next_save_id, next_save_id)) {
                        db_info = std::move(update_result.value());
                    } else {
                        state = manager_result_t{std::move(update_result.error())};
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
                state = db::make_error_result(manager_error_type::begin_transaction_failed,
                                              std::move(begin_result.error()));
            }
        }

        auto completion_on_main = [manager, state = std::move(state), completion = std::move(completion),
                                   saved_datas = std::move(saved_datas), db_info = std::move(db_info)]() mutable {
            if (state) {
                manager->_set_db_info(std::move(db_info));
                auto loaded_objects = manager->_load_and_cache_object_map(saved_datas, false, true);
                manager->_erase_changed_objects(saved_datas);
                completion(manager_map_result_t{std::move(loaded_objects)});
            } else {
                completion(manager_map_result_t{std::move(state.error())});
            }
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->execute(std::move(cancellation), std::move(execution));
}

void manager::revert(db::cancellation_f cancellation, db::revert_preparation_f preparation,
                     db::vector_completion_f completion) {
    auto manager = this->_weak_manager.lock();

    auto execution = [preparation = std::move(preparation), completion = std::move(completion),
                      manager](task const &) mutable {
        // リバートする先のセーブIDをメインスレッドで準備する
        db::integer::type rev_save_id;
        auto preparation_on_main = [&rev_save_id, &preparation]() { rev_save_id = preparation(); };
        thread::perform_sync_on_main(std::move(preparation_on_main));

        auto &db = manager->database();

        manager_result_t state{nullptr};

        db::value_map_vector_map_t reverted_attrs;
        db::object_data_vector_map_t reverted_datas;
        std::optional<db::info> ret_db_info = std::nullopt;

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
                state = manager_result_t{std::move(select_result.error())};
            }

            auto const &entity_models = manager->model().entities();

            if (rev_save_id == current_save_id || last_save_id < rev_save_id) {
                // リバートしようとするセーブIDがカレントと同じかラスト以降ならエラー
                state = db::make_error_result(manager_error_type::out_of_range_save_id);
            } else {
                for (auto const &entity_model_pair : entity_models) {
                    auto const &entity_name = entity_model_pair.first;
                    // リバートするためのデータをデータベースから取得する
                    // カレントとの位置によってredoかundoが内部で呼ばれる
                    if (auto select_result = db::select_for_revert(db, entity_name, rev_save_id, current_save_id)) {
                        reverted_attrs.emplace(entity_name, std::move(select_result.value()));
                    } else {
                        reverted_attrs.clear();
                        state = db::make_error_result(manager_error_type::select_revert_failed,
                                                      std::move(select_result.error()));
                        break;
                    }
                }
            }

            if (state) {
                for (auto const &entity_attrs_pair : reverted_attrs) {
                    auto const &entity_name = entity_attrs_pair.first;
                    auto const &entity_attrs = entity_attrs_pair.second;
                    auto const &rel_models = manager->model().relations(entity_name);

                    // アトリビュートのみのデータから関連のデータを加えてobject_dataを生成する
                    if (auto obj_datas_result =
                            db::make_entity_object_datas(db, entity_name, rel_models, entity_attrs)) {
                        reverted_datas.emplace(entity_name, std::move(obj_datas_result.value()));
                    } else {
                        reverted_attrs.clear();
                        reverted_datas.clear();
                        state = db::make_error_result(manager_error_type::make_object_datas_failed,
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
                    state = manager_result_t{std::move(update_result.error())};
                }
            }

            // トランザクション終了
            if (state) {
                db::commit(db);
            } else {
                db::rollback(db);
                reverted_datas.clear();
                ret_db_info = std::nullopt;
            }
        } else {
            state =
                db::make_error_result(manager_error_type::begin_transaction_failed, std::move(begin_result.error()));
        }

        auto completion_on_main = [manager, state = std::move(state), completion = std::move(completion),
                                   reverted_datas = std::move(reverted_datas),
                                   db_info = std::move(ret_db_info)]() mutable {
            if (state) {
                manager->_set_db_info(std::move(db_info));
                auto loaded_objects = manager->_load_and_cache_object_vector(reverted_datas, false, false);
                completion(manager_vector_result_t{std::move(loaded_objects)});
            } else {
                completion(manager_vector_result_t{std::move(state.error())});
            }
        };

        thread::perform_sync_on_main(std::move(completion_on_main));
    };

    this->execute(std::move(cancellation), std::move(execution));
}

// キャッシュされた単独のオブジェクトをエンティティ名とオブジェクトIDを指定して取得する
std::optional<db::object_ptr> manager::cached_or_created_object(std::string const &entity_name,
                                                                db::object_id const &object_id) const {
    if (object_id.is_temporary()) {
        return this->_inserted_object(entity_name, object_id.temporary());
    } else if (auto object = this->_cached_objects.get(entity_name, object_id)) {
        return object;
    } else {
        return std::nullopt;
    }
}

bool manager::has_created_objects() const {
    for (auto const &entity_pair : this->_created_objects) {
        if (entity_pair.second.size() > 0) {
            return true;
        }
    }

    return false;
}

bool manager::has_changed_objects() const {
    for (auto const &entity_pair : this->_changed_objects) {
        if (entity_pair.second.size() > 0) {
            return true;
        }
    }

    return false;
}

std::size_t manager::created_object_count(std::string const &entity_name) const {
    if (this->_created_objects.count(entity_name) > 0) {
        return this->_created_objects.at(entity_name).size();
    }
    return 0;
}

std::size_t manager::changed_object_count(std::string const &entity_name) const {
    if (this->_changed_objects.count(entity_name) > 0) {
        return this->_changed_objects.at(entity_name).size();
    }
    return 0;
}

observing::syncable manager::observe_db_info(db_info_observing_handler_f &&handler) {
    return this->_db_info->observe(std::move(handler));
}

observing::endable manager::observe_db_object(db_object_observing_handler_f &&handler) {
    return this->_db_object_notifier->observe(std::move(handler));
}

db::object_opt_vector_t manager::relation_objects(db::object_ptr const &object, std::string const &rel_name) const {
    auto const &rel_ids = object->relation_ids(rel_name);
    std::string const &tgt_entity_name = object->entity().relations.at(rel_name).target;
    return to_vector<std::optional<db::object_ptr>>(rel_ids, [this, &tgt_entity_name](db::object_id const &rel_id) {
        return this->cached_or_created_object(tgt_entity_name, rel_id);
    });
}

std::optional<db::object_ptr> manager::relation_object_at(db::object_ptr const &object, std::string const &rel_name,
                                                          std::size_t const idx) const {
    std::string const &tgt_entity_name = object->entity().relations.at(rel_name).target;
    return this->cached_or_created_object(tgt_entity_name, object->relation_id(rel_name, idx));
}

// managerで管理するobjectを作成する
db::object_ptr manager::make_object(std::string const &entity_name) {
    auto obj = db::object::make_shared(this->_model.entity(entity_name));
    auto weak_manager = this->_weak_manager;

    obj->observe([weak_manager](db::object_event const &event) {
           if (auto const manager = weak_manager.lock()) {
               if (event.is_erased()) {
                   manager->_cached_objects.erase(event.entity_name, event.object_id);
               }
               if (event.is_changed()) {
                   manager->_object_did_change(event.object);
               }
           }
       })
        .end()
        ->add_to(this->_pool);

    return obj;
}

void manager::_prepare(manager_ptr const &shared) {
    this->_weak_manager = shared;
}

db::object_ptr manager::_load_and_cache_object(std::string const &entity_name, db::object_data const &data,
                                               bool const force, bool const is_save) {
    if (!data.object_id) {
        throw std::invalid_argument("object_id not found.");
    }

    db::object_ptr object = nullptr;

    if (is_save && this->_created_objects.count(entity_name) > 0) {
        // セーブ時で仮に挿入されたオブジェクトがある場合にオブジェクトを取得
        auto &entity_objects = this->_created_objects.at(entity_name);
        if (entity_objects.size() > 0) {
            auto const &temporary_id = data.object_id.temporary();
            if (entity_objects.count(temporary_id) > 0) {
                object = entity_objects.at(temporary_id);
                entity_objects.erase(temporary_id);

                db::object_id obj_id = object->object_id();
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
        auto manager = this->_weak_manager.lock();
        object = this->_cached_objects.get_or_create(
            entity_name, data.object_id, [&manager, &entity_name]() { return manager->make_object(entity_name); });
    }

    // オブジェクトにデータをロード
    manageable_object::cast(object)->load_data(data, force);

    return object;
}

// 複数のエンティティのデータをロードしてキャッシュする
// ロードされたオブエジェクトはエンティティごとに順番がある状態で返される
db::object_vector_map_t manager::_load_and_cache_object_vector(db::object_data_vector_map_t const &datas,
                                                               bool const force, bool const is_save) {
    db::object_vector_map_t loaded_objects;
    for (auto const &entity_pair : datas) {
        auto const &entity_name = entity_pair.first;
        auto const &entity_datas = entity_pair.second;

        db::object_vector_t objects;
        objects.reserve(entity_datas.size());

        for (db::object_data const &data : entity_datas) {
            auto object = this->_load_and_cache_object(entity_name, data, force, is_save);
            objects.emplace_back(std::move(object));
        }

        loaded_objects.emplace(entity_name, std::move(objects));
    }
    return loaded_objects;
}

// 複数のエンティティのデータをロードしてキャッシュする
// ロードされたオブジェクトはエンティティごとにobject_idをキーとしたmapで返される
db::object_map_map_t manager::_load_and_cache_object_map(db::object_data_vector_map_t const &datas, bool const force,
                                                         bool const is_save) {
    db::object_map_map_t loaded_objects;
    for (auto const &entity_pair : datas) {
        auto const &entity_name = entity_pair.first;
        auto const &entity_datas = entity_pair.second;

        db::object_map_t objects;
        objects.reserve(entity_datas.size());

        for (auto const &data : entity_datas) {
            auto object = this->_load_and_cache_object(entity_name, data, force, is_save);
            objects.emplace(object->object_id().stable(), std::move(object));
        }

        loaded_objects.emplace(entity_name, std::move(objects));
    }
    return loaded_objects;
}

// キャッシュされている全てのオブジェクトをクリアする
void manager::_clear_cached_objects() {
    this->_cached_objects.perform([](std::string const &, db::object_id const &, auto const &object) {
        manageable_object::cast(object)->clear_data();
    });
    this->_cached_objects.clear();
}

// キャッシュされている全てのオブジェクトをパージする（save_idを全て1にする）
// データベースのパージが成功した時に呼ばれる
void manager::_purge_cached_objects() {
    // キャッシュされたオブジェクトのセーブIDを全て1にする
    db::value one_value{db::integer::type{1}};
    this->_cached_objects.perform(
        [one_value = std::move(one_value)](std::string const &, db::object_id const &, auto &object) {
            manageable_object::cast(object)->load_save_id(one_value);
        });
}

// データベース情報を置き換える
void manager::_set_db_info(db::info_opt &&info) {
    this->_db_info->set_value(std::move(info));
}

// データベースに保存するために、全てのエンティティで変更のあったオブジェクトのobject_dataを取得する
db::object_data_vector_map_t manager::_changed_datas_for_save() {
    db::object_data_vector_map_t changed_datas;
    db::object_id_pool obj_id_pool;

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
                auto data = object->save_data(obj_id_pool);
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
                auto data = object->save_data(obj_id_pool);
                if (data.attributes.size() > 0) {
                    entity_datas.emplace_back(std::move(data));
                } else {
                    throw "object_data.attributes is empty.";
                }
                manageable_object::cast(object)->set_status(db::object_status::updating);
            }
        }

        changed_datas.emplace(entity_name, std::move(entity_datas));
    }

    return changed_datas;
}

// リセットするために、全てのエンティティで変更のあったオブジェクトのobject_idを取得する
db::integer_set_map_t manager::_changed_object_ids_for_reset() {
    db::integer_set_map_t changed_obj_ids;

    for (auto const &entity_pair : this->_changed_objects) {
        auto const &entity_name = entity_pair.first;
        auto const &entity_objects = entity_pair.second;

        db::integer_set_t entity_ids;

        for (auto const &object_pair : entity_objects) {
            auto const &object = object_pair.second;
            entity_ids.insert(object->object_id().stable());
        }

        if (entity_ids.size() > 0) {
            changed_obj_ids.emplace(entity_name, std::move(entity_ids));
        }
    }

    return changed_obj_ids;
}

// object_datasに含まれるオブジェクトIDと一致するものは_changed_objectsから取り除く
// データベースに保存された後などに呼ばれる。
void manager::_erase_changed_objects(db::object_data_vector_map_t const &object_datas) {
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

std::optional<db::object_ptr> manager::_inserted_object(std::string const &entity_name,
                                                        std::string const &tmp_obj_id) const {
    if (this->_created_objects.count(entity_name) > 0) {
        auto const &entity_objects = this->_created_objects.at(entity_name);
        if (entity_objects.count(tmp_obj_id) > 0) {
            if (auto const &object = entity_objects.at(tmp_obj_id)) {
                return object;
            }
        }
    }
    return std::nullopt;
}

// バックグラウンドでデータベースの処理をする
void manager::_execute(db::cancellation_f &&cancellation, db::execution_f &&execution) {
    auto op_lambda = [cancellation = std::move(cancellation), execution = std::move(execution),
                      manager = this->_weak_manager.lock()](task const &task) mutable {
        if (!task.is_canceled() && !cancellation()) {
            auto const &db = manager->_database;
            db->open();
            execution(task);
            db->close();
        }
    };

    this->_task_queue.push_back(task::make_shared(std::move(op_lambda)));
}

// バックグラウンドでデータベースからオブジェクトデータを取得する。条件はselect_optionで指定。単独のエンティティのみ
void manager::_execute_fetch_object_datas(
    db::cancellation_f &&cancellation, db::fetch_option_preparation_f &&preparation,
    std::function<void(manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas)> &&completion) {
    auto execution = [preparation = std::move(preparation), completion = std::move(completion),
                      manager = this->_weak_manager.lock()](task const &) mutable {
        // データベースからデータを取得する条件をメインスレッドで準備する
        db::fetch_option fetch_option;
        auto preparation_on_main = [&fetch_option, &preparation]() { fetch_option = preparation(); };
        thread::perform_sync_on_main(std::move(preparation_on_main));

        auto const &db = manager->database();
        auto const &model = manager->model();
        manager_result_t state{nullptr};
        db::object_data_vector_map_t fetched_datas;

        if (auto begin_result = db::begin_transaction(db)) {
            // トランザクション開始
            if (auto fetch_result = db::fetch(db, model, fetch_option)) {
                fetched_datas = std::move(fetch_result.value());
            } else {
                state = manager_result_t{std::move(fetch_result.error())};
            }

            // トランザクション終了
            if (state) {
                db::commit(db);
            } else {
                db::rollback(db);
                fetched_datas.clear();
            }
        } else {
            state =
                db::make_error_result(manager_error_type::begin_transaction_failed, std::move(begin_result.error()));
        }

        // 結果を返す
        completion(std::move(state), std::move(fetched_datas));
    };

    this->_execute(std::move(cancellation), std::move(execution));
}

// バックグラウンドでデータベースからオブジェクトデータを取得する。条件はobject_idで指定。単独のエンティティのみ
void manager::_execute_fetch_object_datas(
    db::cancellation_f &&cancellation, fetch_ids_preparation_f &&ids_preparation,
    std::function<void(manager_result_t &&state, db::object_data_vector_map_t &&fetched_datas)> &&completion) {
    db::fetch_option_preparation_f opt_preparation = [ids_preparation = std::move(ids_preparation)]() {
        return db::to_fetch_option(ids_preparation());
    };

    this->_execute_fetch_object_datas(std::move(cancellation), std::move(opt_preparation), std::move(completion));
}

// オブジェクトに変更があった時の処理
void manager::_object_did_change(db::object_ptr const &object) {
    auto const &entity_name = object->entity_name();

    if (object->status() == db::object_status::created) {
        // 仮に挿入された状態の場合
        if (this->_created_objects.count(entity_name) > 0 && object->is_removed()) {
            // オブジェクトが削除されていたら、_created_objectsからも削除
            this->_created_objects.at(entity_name).erase(object->object_id().temporary());
        }
    } else {
        // 挿入されたのではない場合
        if (this->_changed_objects.count(entity_name) == 0) {
            // _changed_objectsにエンティティのmapがなければ生成する
            this->_changed_objects.insert(std::make_pair(entity_name, db::object_map_t{}));
        }

        // _changed_objectsにオブジェクトを追加
        auto const &obj_id = object->object_id().stable();
        if (this->_changed_objects.at(entity_name).count(obj_id) == 0) {
            this->_changed_objects.at(entity_name).emplace(obj_id, object);
        }
    }

    if (object->is_removed()) {
        // オブジェクトが削除されていたら逆関連も削除する
        for (auto const &entity_pair : this->_model.entity(entity_name).inverse_relation_names) {
            auto const &inv_entity_name = entity_pair.first;
            auto const &inv_rel_names = entity_pair.second;

            this->_cached_objects.perform_entity(
                inv_entity_name, [&inv_rel_names, &object](std::string const &, db::object_id const &,
                                                           db::object_ptr const &inv_rel_obj) {
                    for (auto const &inv_rel_name : inv_rel_names) {
                        inv_rel_obj->remove_relation_id(inv_rel_name, object->object_id());
                    }
                });
        }
    }

    // オブジェクトが変更された通知を送信
    this->_db_object_notifier->notify(object);
}

manager_ptr manager::make_shared(std::string const &db_path, db::model const &model, std::size_t const priority_count) {
    auto shared = manager_ptr(new manager{db_path, model, priority_count});
    shared->_prepare(shared);
    return shared;
}
