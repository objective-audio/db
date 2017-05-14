//
//  yas_db_manager.cpp
//

#include "yas_db_additional_utils.h"
#include "yas_db_attribute.h"
#include "yas_db_entity.h"
#include "yas_db_model.h"
#include "yas_db_object_utils.h"
#include "yas_db_relation.h"
#include "yas_db_select_option.h"
#include "yas_db_sql_utils.h"
#include "yas_db_utils.h"
#include "yas_each_index.h"
#include "yas_objc_macros.h"
#include "yas_observing.h"
#include "yas_operation.h"
#include "yas_result.h"
#include "yas_stl_utils.h"
#include "yas_unless.h"
#include "yas_version.h"

using namespace yas;

#pragma mark - error

db::manager::error::error(std::nullptr_t) : _type(), _db_error(nullptr) {
}

db::manager::error::error(error_type const error_type, db::error db_error)
    : _type(error_type), _db_error(std::move(db_error)) {
}

db::manager::error::operator bool() const {
    return this->_type != db::manager::error_type::none;
}

db::manager::error_type const &db::manager::error::type() const {
    return this->_type;
}

db::error const &db::manager::error::database_error() const {
    return this->_db_error;
}

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
    db::value_map_t _db_info;
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
    bool load_object_data(db::object &object, std::string const &entity_name, db::object_data const &data,
                          bool const force) {
        if (this->_cached_objects.count(entity_name) == 0) {
            this->_cached_objects.emplace(std::make_pair(entity_name, db::weak_object_map_t{}));
        }

        auto manager = cast<db::manager>();
        auto &entity_cached_objects = this->_cached_objects.at(entity_name);

        if (data.attributes.count(object_id_field) > 0) {
            if (auto const &object_id_value = data.attributes.at(db::object_id_field)) {
                auto const &object_id = object_id_value.get<db::integer>();

                if (object) {
                    entity_cached_objects.emplace(std::make_pair(object_id, to_weak(object)));
                } else {
                    if (entity_cached_objects.count(object_id) > 0) {
                        if (auto const &weak_object = entity_cached_objects.at(object_id)) {
                            object = weak_object.lock();
                            if (!object) {
                                throw "cached object is released. entity_name (" + entity_name + ") object_id (" +
                                    std::to_string(object_id) + ")";
                                ;
                            }
                        }
                    }

                    if (!object) {
                        object = db::object{manager, this->_model.entity(entity_name)};
                        entity_cached_objects.emplace(std::make_pair(object_id, to_weak(object)));
                    }
                }

                object.manageable().load_data(data, force);

                return true;
            }
        } else {
            throw "object_id not found.";
        }

        return false;
    }

    // 複数のエンティティのデータをロードする
    // エンティティごとのオブジェクトは順番がある状態で返される
    db::object_vector_map_t load_vector_object_datas(db::object_data_vector_map_t const &datas, bool const force,
                                                     bool const is_save) {
        db::object_vector_map_t loaded_objects;
        for (auto const &entity_pair : datas) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_datas = entity_pair.second;

            db::object_vector_t objects;
            objects.reserve(entity_datas.size());

            for (auto const &data : entity_datas) {
                auto object = db::object::null_object();
                // セーブ時で仮に挿入されたオブジェクトがある場合
                if (is_save && this->_inserted_objects.count(entity_name)) {
                    auto &entity_objects = this->_inserted_objects.at(entity_name);
                    if (entity_objects.size() > 0) {
                        // 前から順に消していけば一致している？
                        // 後から挿入されたオブジェクトが間違えて消されることはないか？
                        object = entity_objects.front();
                        entity_objects.pop_front();

                        if (entity_objects.size() == 0) {
                            this->_inserted_objects.erase(entity_name);
                        }
                    }
                }

                if (this->load_object_data(object, entity_name, data, force)) {
                    objects.emplace_back(std::move(object));
                }
            }

            loaded_objects.emplace(std::make_pair(entity_name, std::move(objects)));
        }
        return loaded_objects;
    }

    // 複数のエンティティのデータをロードする
    // エンティティごとのオブジェクトはobject_idをキーとしたmapで返される
    db::object_map_map_t load_map_object_datas(db::object_data_vector_map_t const &datas, bool const force) {
        db::object_map_map_t loaded_objects;
        for (auto const &entity_pair : datas) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_datas = entity_pair.second;

            db::object_map_t objects;
            objects.reserve(entity_datas.size());

            for (auto const &data : entity_datas) {
                auto object = db::object::null_object();
                if (this->load_object_data(object, entity_name, data, force)) {
                    objects.emplace(std::make_pair(object.object_id().get<db::integer>(), std::move(object)));
                }
            }

            loaded_objects.emplace(std::make_pair(entity_name, std::move(objects)));
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
    void purge_cached_objects() {
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
    void set_db_info(db::value_map_t &&info) {
        this->_db_info = std::move(info);

        if (this->_subject.has_observer()) {
            this->_subject.notify(db::manager::method::db_info_changed);
        }
    }

    // データベースに保存するために、全てのエンティティで変更のあったオブジェクトのobject_dataを取得する
    db::object_data_vector_map_t changed_datas_for_save() {
        db::object_data_vector_map_t changed_datas;

        for (auto const &entity_pair : this->_model.entities()) {
            auto const &entity_name = entity_pair.first;

            std::size_t const inserted_count =
                this->_inserted_objects.count(entity_name) ? this->_inserted_objects.at(entity_name).size() : 0;
            std::size_t const changed_count =
                this->_changed_objects.count(entity_name) ? _changed_objects.at(entity_name).size() : 0;
            std::size_t const total_count = inserted_count + changed_count;

            if (total_count > 0) {
                db::object_data_vector_t entity_datas;
                entity_datas.reserve(total_count);

                if (inserted_count > 0) {
                    auto const &entity_objects = this->_inserted_objects.at(entity_name);

                    for (auto object : entity_objects) {
                        auto data = object.data_for_save();
                        if (data.attributes.size() > 0) {
                            entity_datas.emplace_back(std::move(data));
                        } else {
                            throw "object_data.attributes is empty.";
                        }
                    }
                }

                if (changed_count > 0) {
                    auto const &entity_objects = this->_changed_objects.at(entity_name);

                    for (auto const &object_pair : entity_objects) {
                        auto object = object_pair.second;
                        auto data = object.data_for_save();
                        if (data.attributes.size() > 0) {
                            entity_datas.emplace_back(std::move(data));
                        } else {
                            throw "object_data.attributes is empty.";
                        }
                        object.manageable().set_status(db::object_status::updating);
                    }
                }

                if (entity_datas.size() > 0) {
                    changed_datas.emplace(std::make_pair(entity_name, std::move(entity_datas)));
                }
            }
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
                auto object = object_pair.second;
                entity_ids.insert(object.object_id().get<db::integer>());
            }

            if (entity_ids.size() > 0) {
                changed_obj_ids.emplace(std::make_pair(entity_name, std::move(entity_ids)));
            }
        }

        return changed_obj_ids;
    }

    // object_datasに含まれるオブジェクトIDと一致するものは_changed_objectsから取り除く。データベースに保存された後などに呼ばれる。
    void erase_changed_objects(db::object_data_vector_map_t const &object_datas) {
        for (auto &entity_pair : object_datas) {
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
            auto &entity_objects = this->_cached_objects.at(entity_name);
            if (entity_objects.count(object_id) > 0) {
                if (auto const &weak_object = entity_objects.at(object_id)) {
                    if (auto object = weak_object.lock()) {
                        return object;
                    }
                }
            }
        }
        return db::object::null_object();
    }

    // オブジェクトに変更があった時の処理
    void _object_did_change(db::object const &object) {
        auto const &entity_name = object.entity_name();

        if (object.status() == db::object_status::inserted) {
            if (this->_inserted_objects.count(entity_name) > 0 && object.is_removed()) {
                erase_if(this->_inserted_objects.at(entity_name),
                         [&object](auto const &inserted_object) { return inserted_object == object; });
            }
        } else {
            if (this->_changed_objects.count(entity_name) == 0) {
                this->_changed_objects.insert(std::make_pair(entity_name, db::object_map_t{}));
            }

            this->_changed_objects.at(entity_name)
                .emplace(std::make_pair(object.object_id().get<db::integer>(), object));
        }

        if (this->_subject.has_observer()) {
            this->_subject.notify(db::manager::method::object_changed, db::manager::change_info{object});
        }
    }

    // オブジェクトが解放された時の処理
    void _object_did_erase(std::string const &entity_name, db::integer::type const object_id) {
        if (this->_cached_objects.count(entity_name) > 0) {
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
    void execute_setup(std::function<void(db::manager::result_t &&, db::value_map_t &&)> &&completion,
                       operation_option_t &&option) {
        this->execute([completion = std::move(completion), manager = cast<manager>()](operation const &op) mutable {
            auto &db = manager.database();
            auto const &model = manager.model();

            db::value_map_t db_info;
            db::manager::result_t state{nullptr};

            if (auto begin_result = db::begin_transaction(db)) {
                if (db::table_exists(db, db::info_table)) {
                    bool needs_migration = false;

                    if (auto select_result = db::select(
                            db, {.table = info_table, .fields = {db::version_field}, .limit_range = db::range{0, 1}})) {
                        auto const update_info_result = db.execute_update(
                            update_sql(db::info_table, {db::version_field}), {db::value{model.version().str()}});
                        if (update_info_result) {
                            auto const &infos = select_result.value();
                            auto const &info = *infos.rbegin();
                            if (info.count(db::version_field) == 0) {
                                state = db::make_error_result(db::manager::error_type::version_not_found);
                            } else {
                                auto db_version_str = info.at(db::version_field).get<db::text>();
                                if (db_version_str.size() == 0) {
                                    state = db::make_error_result(error_type::invalid_version_text);
                                } else {
                                    auto const db_version = yas::version{db_version_str};
                                    if (db_version < model.version()) {
                                        needs_migration = true;
                                    }
                                }
                            }
                        } else {
                            state = db::make_error_result(error_type::update_info_failed,
                                                          std::move(update_info_result.error()));
                        }
                    } else {
                        state = db::make_error_result(error_type::select_info_failed, std::move(select_result.error()));
                    }

                    if (state && needs_migration) {
                        for (auto const &entity_pair : model.entities()) {
                            auto const &entity_name = entity_pair.first;
                            auto const &entity = entity_pair.second;

                            if (db::table_exists(db, entity_name)) {
                                // alter table
                                for (auto const &attr_pair : entity.all_attributes) {
                                    if (!db::column_exists(db, attr_pair.first, entity_name)) {
                                        auto const &attr = attr_pair.second;
                                        if (auto ul =
                                                unless(db.execute_update(alter_table_sql(entity_name, attr.sql())))) {
                                            state = db::make_error_result(error_type::alter_entity_table_failed,
                                                                          std::move(ul.value.error()));
                                            break;
                                        }
                                    }
                                }
                            } else {
                                // create table
                                if (auto ul = unless(db.execute_update(entity.sql_for_create()))) {
                                    state = db::make_error_result(error_type::create_entity_table_failed,
                                                                  std::move(ul.value.error()));
                                    break;
                                }
                            }

                            if (state) {
                                for (auto &rel_pair : entity.relations) {
                                    if (auto ul = unless(db.execute_update(rel_pair.second.sql_for_create()))) {
                                        state = db::make_error_result(error_type::create_relation_table_failed,
                                                                      std::move(ul.value.error()));
                                        break;
                                    }
                                }
                            }

                            if (!state) {
                                break;
                            }
                        }

                        if (state) {
                            // create indices
                            for (auto const &index_pair : model.indices()) {
                                if (!db::index_exists(db, index_pair.first)) {
                                    auto &index = index_pair.second;
                                    if (auto ul = unless(db.execute_update(index.sql_for_create()))) {
                                        state = db::make_error_result(error_type::create_index_failed,
                                                                      std::move(ul.value.error()));
                                        break;
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // create information table

                    if (auto create_result = db.execute_update(db::create_table_sql(
                            db::info_table, {db::version_field, db::current_save_id_field, db::last_save_id_field}))) {
                        db::value_vector_t args{db::value{model.version().str()}, db::value{integer::type{0}},
                                                db::value{integer::type{0}}};
                        if (auto ul = unless(db.execute_update(
                                db::insert_sql(info_table,
                                               {db::version_field, db::current_save_id_field, db::last_save_id_field}),
                                args))) {
                            state = db::make_error_result(error_type::insert_info_failed, std::move(ul.value.error()));
                        }
                    } else {
                        state = db::make_error_result(error_type::create_info_table_failed,
                                                      std::move(create_result.error()));
                    }

                    // create entity tables

                    if (state) {
                        auto const &entities = model.entities();
                        for (auto &entity_pair : entities) {
                            auto &entity = entity_pair.second;
                            if (auto ul = unless(db.execute_update(entity.sql_for_create()))) {
                                state = db::make_error_result(error_type::create_entity_table_failed,
                                                              std::move(ul.value.error()));
                                break;
                            }

                            for (auto &rel_pair : entity.relations) {
                                if (auto ul = unless(db.execute_update(rel_pair.second.sql_for_create()))) {
                                    state = db::make_error_result(error_type::create_relation_table_failed,
                                                                  std::move(ul.value.error()));
                                    break;
                                }
                            }

                            if (!state) {
                                break;
                            }
                        }
                    }

                    // create indices

                    if (state) {
                        for (auto const &index_pair : model.indices()) {
                            auto &index = index_pair.second;
                            if (auto ul = unless(db.execute_update(index.sql_for_create()))) {
                                state =
                                    db::make_error_result(error_type::create_index_failed, std::move(ul.value.error()));
                                break;
                            }
                        }
                    }
                }

                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                }
            } else {
                state = db::make_error_result(error_type::begin_transaction_failed, std::move(begin_result.error()));
            }

            if (state) {
                if (auto select_result = select_db_info(db)) {
                    db_info = std::move(select_result.value());
                } else {
                    state = db::make_error_result(error_type::select_info_failed, std::move(select_result.error()));
                }
            }

            completion(std::move(state), std::move(db_info));
        },
                      std::move(option));
    }

    // バックグラウンドでデータベース上のデータをクリアする
    void execute_clear(std::function<void(db::manager::result_t &&, db::value_map_t &&)> &&completion,
                       operation_option_t &&option) {
        this->execute([completion = std::move(completion), manager = cast<manager>()](operation const &op) mutable {
            auto &db = manager.database();
            auto const &model = manager.model();

            db::value_map_t db_info;
            db::manager::result_t state{nullptr};

            if (auto begin_result = db::begin_transaction(db)) {
                for (auto const &entity_pair : model.entities()) {
                    auto const &entity = entity_pair.second;
                    auto const &table_name = entity.name;

                    if (auto delete_result = db.execute_update(db::delete_sql(table_name))) {
                        for (auto const &rel_pair : entity.relations) {
                            auto const table_name = rel_pair.second.table_name;

                            if (auto ul = unless(db.execute_update(db::delete_sql(table_name)))) {
                                state = db::make_error_result(error_type::delete_failed, std::move(ul.value.error()));
                                break;
                            }
                        }
                    } else {
                        state = db::make_error_result(error_type::delete_failed, std::move(delete_result.error()));
                        break;
                    }
                }
            } else {
                state = db::make_error_result(error_type::begin_transaction_failed, std::move(begin_result.error()));
            }

            if (state) {
                auto const sql = update_sql(db::info_table, {db::current_save_id_field, db::last_save_id_field});
                db::value_vector_t const params{db::value{db::integer::type{0}}, db::value{db::integer::type{0}}};
                if (auto update_result = db.execute_update(sql, params)) {
                    if (auto select_result = db::select_db_info(db)) {
                        db_info = std::move(select_result.value());
                    } else {
                        state = db::make_error_result(error_type::select_info_failed, std::move(select_result.error()));
                    }
                } else {
                    state = db::make_error_result(error_type::update_info_failed, std::move(update_result.error()));
                }
            }

            if (state) {
                db::commit(db);
            } else {
                db::rollback(db);
                db_info.clear();
            }

            completion(std::move(state), std::move(db_info));
        },
                      std::move(option));
    }

    // バックグラウンドでデータベース上のデータをパージする
    void execute_purge(std::function<void(db::manager::result_t &&, db::value_map_t &&)> &&completion,
                       operation_option_t &&option) {
        this->execute([completion = std::move(completion), manager = cast<manager>()](operation const &op) mutable {
            auto &db = manager.database();
            auto const &model = manager.model();

            db::value const one_value = db::value{db::integer::type{1}};

            db::value_map_t db_info;
            db::manager::result_t state{nullptr};

            if (auto begin_result = db::begin_transaction(db)) {
                auto current_save_id = db::value::null_value();
                auto last_save_id = db::value::null_value();

                if (auto select_result = db::select_db_info(db)) {
                    auto const &db_info = select_result.value();
                    if (db_info.count(db::current_save_id_field) > 0) {
                        current_save_id = db_info.at(db::current_save_id_field);
                    } else {
                        state = db::make_error_result(error_type::save_id_not_found);
                    }

                    if (db_info.count(db::last_save_id_field) > 0) {
                        last_save_id = db_info.at(db::last_save_id_field);
                    } else {
                        state = db::make_error_result(error_type::save_id_not_found);
                    }
                } else {
                    state = db::make_error_result(error_type::select_info_failed, std::move(select_result.error()));
                }

                if (state && current_save_id && last_save_id) {
                    if (current_save_id.get<db::integer>() < last_save_id.get<db::integer>()) {
                        state = db::delete_next_to_last(db, model, current_save_id);
                    }
                }

                if (state) {
                    for (auto const &entity_pair : model.entities()) {
                        auto const &entity_name = entity_pair.first;
                        auto const &entity = entity_pair.second;

                        if (auto purge_result = db::purge(db, entity_name)) {
                            auto const update_entity_sql = db::update_sql(entity_name, {db::save_id_field});
                            if (auto update_result = db.execute_update(update_entity_sql, {one_value})) {
                                for (auto const &rel_pair : entity.relations) {
                                    auto const &relation = rel_pair.second;
                                    auto const &rel_table_name = relation.table_name;

                                    if (auto purge_rel_result = db::purge_relation(db, rel_table_name, entity_name)) {
                                        auto const update_rel_sql = db::update_sql(rel_table_name, {db::save_id_field});
                                        if (auto ul = unless(db.execute_update(update_rel_sql, {one_value}))) {
                                            state = db::make_error_result(error_type::update_save_id_failed,
                                                                          std::move(ul.value.error()));
                                        }
                                    } else {
                                        state = db::make_error_result(error_type::purge_relation_failed,
                                                                      std::move(purge_rel_result.error()));
                                    }
                                }
                            } else {
                                state = db::make_error_result(error_type::update_save_id_failed,
                                                              std::move(update_result.error()));
                            }
                        } else {
                            state = db::make_error_result(error_type::purge_failed, std::move(purge_result.error()));
                            break;
                        }

                        if (!state) {
                            break;
                        }
                    }
                }

                if (state) {
                    auto const sql =
                        update_sql(db::info_table, {db::current_save_id_field, db::last_save_id_field}, "");
                    db::value_vector_t const args{one_value, one_value};
                    if (auto update_result = db.execute_update(sql, args)) {
                        if (auto select_result = db::select_db_info(db)) {
                            db_info = select_result.value();
                        } else {
                            state =
                                db::make_error_result(error_type::select_info_failed, std::move(select_result.error()));
                        }
                    } else {
                        state = db::make_error_result(error_type::update_info_failed, std::move(update_result.error()));
                    }
                }

                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                    db_info.clear();
                }
            } else {
                state = db::make_error_result(error_type::begin_transaction_failed, std::move(begin_result.error()));
            }

            if (state) {
                if (auto ul = unless(db.execute_update(db::vacuum_sql()))) {
                    state = db::make_error_result(error_type::vacuum_failed, std::move(ul.value.error()));
                }
            }

            completion(std::move(state), std::move(db_info));
        },
                      std::move(option));
    }

    // バックグラウンドでデータベース上にオブジェクトデータを挿入する
    void execute_insert(
        insert_preparation_values_f &&preparation,
        std::function<void(db::manager::result_t &&, db::object_data_vector_map_t &&, db::value_map_t &&)> &&completion,
        operation_option_t &&option) {
        this->execute(
            [preparation = std::move(preparation), completion = std::move(completion),
             manager = cast<manager>()](operation const &op) mutable {
                db::value_map_vector_map_t values;

                auto preparation_on_main = [&values, &preparation]() { values = preparation(); };

                dispatch_sync(manager.dispatch_queue(), std::move(preparation_on_main));

                auto &db = manager.database();
                auto const &model = manager.model();

                db::value_map_t db_info;
                object_data_vector_map_t inserted_datas;
                db::integer::type start_obj_id = 1;

                db::manager::result_t state{nullptr};

                if (auto begin_result = db::begin_transaction(db)) {
                    auto current_save_id = db::value::null_value();
                    auto last_save_id = db::value::null_value();
                    auto next_save_id = db::value::null_value();

                    if (auto select_result = db::select_db_info(db)) {
                        auto const &db_info = select_result.value();
                        if (db_info.count(db::current_save_id_field) > 0) {
                            current_save_id = db_info.at(db::current_save_id_field);
                            next_save_id = db::value{current_save_id.get<db::integer>() + 1};
                        } else {
                            state = db::make_error_result(error_type::save_id_not_found);
                        }

                        if (db_info.count(db::last_save_id_field) > 0) {
                            last_save_id = db_info.at(db::last_save_id_field);
                        } else {
                            state = db::make_error_result(error_type::save_id_not_found);
                        }
                    } else {
                        state = db::make_error_result(error_type::select_info_failed, std::move(select_result.error()));
                    }

                    if (state && current_save_id && last_save_id) {
                        if (current_save_id.get<db::integer>() < last_save_id.get<db::integer>()) {
                            state = db::delete_next_to_last(db, model, current_save_id);
                        }
                    }

                    if (state) {
                        for (auto &values_pair : values) {
                            auto const &entity_name = values_pair.first;
                            auto &entity_values = values_pair.second;

                            if (auto max_value = db::max(db, entity_name, db::object_id_field)) {
                                start_obj_id = max_value.get<db::integer>() + 1;
                            }

                            std::size_t idx = 0;
                            for (auto &obj_values : entity_values) {
                                db::value obj_id_value{start_obj_id + idx};

                                std::vector<std::string> fields{db::object_id_field, db::save_id_field};
                                db::value_vector_t args{obj_id_value, next_save_id};

                                fields.reserve(obj_values.size() + 2);
                                args.reserve(obj_values.size() + 2);

                                for (auto &value : obj_values) {
                                    fields.push_back(value.first);
                                    args.emplace_back(std::move(value.second));
                                }

                                auto sql = db::insert_sql(entity_name, fields);
                                if (auto ul = unless(db.execute_update(std::move(sql), std::move(args)))) {
                                    state = db::make_error_result(error_type::insert_attributes_failed,
                                                                  std::move(ul.value.error()));
                                    break;
                                }

                                db::select_option option{
                                    .table = entity_name,
                                    .where_exprs = db::equal_field_expr(db::object_id_field),
                                    .arguments = {{std::make_pair(db::object_id_field, obj_id_value)}}};

                                auto select_result = db::select(db, std::move(option));
                                if (select_result) {
                                    if (inserted_datas.count(entity_name) == 0) {
                                        db::object_data_vector_t entity_datas{};
                                        entity_datas.reserve(entity_values.size());
                                        inserted_datas.emplace(std::make_pair(entity_name, std::move(entity_datas)));
                                    }

                                    inserted_datas.at(entity_name)
                                        .emplace_back(
                                            db::object_data{.attributes = std::move(select_result.value().at(0))});
                                } else {
                                    state = db::make_error_result(error_type::select_failed,
                                                                  std::move(select_result.error()));
                                    break;
                                }

                                ++idx;
                            }
                        }
                    }

                    if (state) {
                        auto const sql =
                            update_sql(db::info_table, {db::current_save_id_field, db::last_save_id_field});
                        db::value_vector_t const args{next_save_id, next_save_id};
                        if (auto update_result = db.execute_update(sql, args)) {
                            if (auto select_result = db::select_db_info(db)) {
                                db_info = select_result.value();
                            } else {
                                state = db::make_error_result(error_type::select_info_failed,
                                                              std::move(select_result.error()));
                            }
                        } else {
                            state =
                                db::make_error_result(error_type::update_info_failed, std::move(update_result.error()));
                        }
                    }

                    if (state) {
                        db::commit(db);
                    } else {
                        db::rollback(db);
                        inserted_datas.clear();
                    }
                } else {
                    state =
                        db::make_error_result(error_type::begin_transaction_failed, std::move(begin_result.error()));
                }

                completion(std::move(state), std::move(inserted_datas), std::move(db_info));
            },
            std::move(option));
    }

    // バックグラウンドでデータベースからオブジェクトデータを取得する。条件はselect_optionで指定。単独のエンティティのみ
    void execute_fetch_object_datas(
        fetch_preparation_option_f &&preparation,
        std::function<void(db::manager::result_t &&state, db::object_data_vector_map_t &&fetched_datas)> &&completion,
        operation_option_t &&option) {
        this->execute(
            [preparation = std::move(preparation), completion = std::move(completion),
             manager = cast<db::manager>()](operation const &) mutable {
                db::select_option option;

                auto preparation_on_main = [&option, &preparation]() { option = preparation(); };

                dispatch_sync(manager.dispatch_queue(), std::move(preparation_on_main));

                std::string const entity_name = option.table;

                auto &db = manager.database();

                auto const &rel_models = manager.model().relations(entity_name);
                db::manager::result_t state{nullptr};

                db::object_data_vector_map_t fetched_datas;

                if (auto begin_result = db::begin_transaction(db)) {
                    auto current_save_id = db::value::null_value();
                    auto cur_save_id_result = db::select_current_save_id(db);
                    if (cur_save_id_result) {
                        current_save_id = std::move(cur_save_id_result.value());

                        if (auto select_result = db::select_last(db, std::move(option), current_save_id)) {
                            auto &entity_attrs = select_result.value();
                            if (auto obj_datas_result =
                                    db::make_entity_object_datas(db, entity_name, rel_models, entity_attrs)) {
                                auto &entity_obj_datas = obj_datas_result.value();
                                if (entity_obj_datas.size() > 0) {
                                    fetched_datas.emplace(std::make_pair(entity_name, std::move(entity_obj_datas)));
                                }
                            } else {
                                state = db::make_error_result(error_type::fetch_object_datas_failed,
                                                              std::move(obj_datas_result.error()));
                            }
                        } else {
                            state =
                                db::make_error_result(error_type::select_last_failed, std::move(select_result.error()));
                        }
                    } else {
                        state = db::manager::result_t{std::move(cur_save_id_result.error())};
                    }

                    if (state) {
                        db::commit(db);
                    } else {
                        db::rollback(db);
                        fetched_datas.clear();
                    }
                } else {
                    state =
                        db::make_error_result(error_type::begin_transaction_failed, std::move(begin_result.error()));
                }

                completion(std::move(state), std::move(fetched_datas));
            },
            std::move(option));
    }

    // バックグラウンドでデータベースからオブジェクトデータを取得する。条件はobject_idで指定。単独のエンティティのみ
    void execute_fetch_object_datas(
        fetch_preparation_ids_f &&preparation,
        std::function<void(db::manager::result_t &&state, db::object_data_vector_map_t &&fetched_datas)> &&completion,
        operation_option_t &&option) {
        this->execute(
            [completion = std::move(completion), preparation = std::move(preparation),
             manager = cast<manager>()](operation const &) mutable {
                db::integer_set_map_t obj_ids;

                auto preparation_on_main = [&obj_ids, &preparation]() { obj_ids = preparation(); };

                dispatch_sync(manager.dispatch_queue(), std::move(preparation_on_main));

                auto &db = manager.database();

                db::manager::result_t state{nullptr};

                object_data_vector_map_t fetched_datas;

                if (auto begin_result = db::begin_transaction(db)) {
                    auto current_save_id = db::value::null_value();
                    auto cur_save_id_result = db::select_current_save_id(db);
                    if (cur_save_id_result) {
                        current_save_id = std::move(cur_save_id_result.value());

                        for (auto const &entity_pair : obj_ids) {
                            auto const &entity_name = entity_pair.first;
                            auto const &rel_models = manager.model().relations(entity_name);

                            auto const &entity_obj_ids = entity_pair.second;
                            db::select_option option{
                                .table = entity_name,
                                .where_exprs = object_id_field + " in (" +
                                               joined(entity_obj_ids, ",",
                                                      [](auto const &rel_id) { return std::to_string(rel_id); }) +
                                               ")"};

                            if (auto select_result = db::select_last(db, std::move(option), current_save_id)) {
                                auto &entity_attrs = select_result.value();
                                if (auto obj_datas_result =
                                        db::make_entity_object_datas(db, entity_name, rel_models, entity_attrs)) {
                                    fetched_datas.emplace(
                                        std::make_pair(entity_name, std::move(obj_datas_result.value())));
                                } else {
                                    state = db::make_error_result(error_type::fetch_object_datas_failed,
                                                                  std::move(obj_datas_result.error()));
                                    break;
                                }
                            } else {
                                state = db::make_error_result(error_type::select_last_failed,
                                                              std::move(select_result.error()));
                                break;
                            }
                        }
                    } else {
                        state = db::manager::result_t{std::move(cur_save_id_result.error())};
                    }
                } else {
                    state =
                        db::make_error_result(error_type::begin_transaction_failed, std::move(begin_result.error()));
                }

                completion(std::move(state), std::move(fetched_datas));
            },
            std::move(option));
    }

    // バックグラウンドでデータベースにオブジェクトの変更を保存する
    void execute_save(std::function<void(db::manager::result_t &&state, db::object_data_vector_map_t &&saved_datas,
                                         db::value_map_t &&db_info)> &&completion,
                      operation_option_t &&option) {
        this->execute([completion = std::move(completion), manager = cast<manager>()](operation const &) mutable {
            db::object_data_vector_map_t changed_datas;
            auto manager_impl = manager.impl_ptr<impl>();

            auto get_change_lambda = [&manager_impl, &changed_datas]() {
                changed_datas = manager_impl->changed_datas_for_save();
            };

            dispatch_sync(manager.dispatch_queue(), get_change_lambda);

            auto &db = manager.database();
            auto const &model = manager.model();

            db::value_map_t db_info;
            db::object_data_vector_map_t saved_datas;

            db::manager::result_t state{nullptr};

            if (changed_datas.size() > 0) {
                if (auto begin_result = db::begin_transaction(db)) {
                    auto current_save_id = db::value::null_value();
                    auto next_save_id = db::value::null_value();
                    auto last_save_id = db::value::null_value();

                    if (auto select_result = db::select_db_info(db)) {
                        auto const &db_info = select_result.value();
                        if (db_info.count(db::current_save_id_field) > 0) {
                            current_save_id = db_info.at(db::current_save_id_field);
                            next_save_id = db::value{current_save_id.get<db::integer>() + 1};
                        } else {
                            state = db::make_error_result(error_type::save_id_not_found);
                        }

                        if (db_info.count(db::last_save_id_field) > 0) {
                            last_save_id = db_info.at(db::last_save_id_field);
                        } else {
                            state = db::make_error_result(error_type::save_id_not_found);
                        }
                    } else {
                        state = db::make_error_result(error_type::select_info_failed, std::move(select_result.error()));
                    }

                    if (state && next_save_id && current_save_id && last_save_id && next_save_id.get<integer>() > 0) {
                        if (current_save_id.get<db::integer>() < last_save_id.get<db::integer>()) {
                            state = db::delete_next_to_last(db, model, current_save_id);
                        }
                    } else {
                        state = db::make_error_result(error_type::save_id_not_found);
                    }

                    if (state) {
                        auto const &save_id_pair = std::make_pair(db::save_id_field, next_save_id);

                        for (auto const &entity_pair : changed_datas) {
                            auto const &entity_name = entity_pair.first;
                            auto const &changed_entity_datas = entity_pair.second;
                            auto const entity_insert_sql = manager.model().entity(entity_name).sql_for_insert();
                            auto const &rel_models = manager.model().relations(entity_name);

                            db::object_data_vector_t entity_saved_datas;

                            for (auto data : changed_entity_datas) {
                                erase_if_exists(data.attributes, id_field);
                                replace(data.attributes, db::save_id_field, next_save_id);

                                if (data.attributes.count(object_id_field) == 0) {
                                    db::integer::type obj_id = 0;
                                    if (auto max_value = db::max(db, entity_name, db::object_id_field)) {
                                        obj_id = max_value.get<db::integer>();
                                    }
                                    replace(data.attributes, db::object_id_field, db::value{obj_id + 1});
                                }

                                if (auto insert_result = db.execute_update(entity_insert_sql, data.attributes)) {
                                    if (auto row_result = db.last_insert_row_id()) {
                                        auto const src_rowid_pair =
                                            std::make_pair(db::src_id_field, db::value{row_result.value()});
                                        auto const src_obj_id_pair =
                                            std::make_pair(db::src_obj_id_field, data.attributes.at(object_id_field));

                                        for (auto const &rel_pair : data.relations) {
                                            auto const &rel_name = rel_pair.first;
                                            auto const &rel = rel_pair.second;
                                            auto const &rel_model = rel_models.at(rel_name);
                                            auto const &rel_insert_sql = rel_model.sql_for_insert();

                                            for (auto const &rel_tgt_obj_id : rel) {
                                                auto tgt_obj_id_pair =
                                                    std::make_pair(db::tgt_obj_id_field, rel_tgt_obj_id);
                                                db::value_map_t args{src_rowid_pair, src_obj_id_pair,
                                                                     std::move(tgt_obj_id_pair), save_id_pair};
                                                if (auto ul =
                                                        unless(db.execute_update(rel_insert_sql, std::move(args)))) {
                                                    state = db::make_error_result(error_type::insert_relation_failed,
                                                                                  std::move(ul.value.error()));
                                                    break;
                                                }
                                            }
                                        }
                                    } else {
                                        state = db::make_error_result(error_type::last_insert_rowid_failed,
                                                                      std::move(row_result.error()));
                                    }
                                } else {
                                    state = db::make_error_result(error_type::insert_attributes_failed,
                                                                  std::move(insert_result.error()));
                                }

                                if (state) {
                                    entity_saved_datas.emplace_back(std::move(data));
                                }
                            }

                            if (!state) {
                                break;
                            }

                            saved_datas.emplace(std::make_pair(entity_name, std::move(entity_saved_datas)));
                        }
                    }

                    if (state) {
                        auto const sql =
                            update_sql(db::info_table, {db::current_save_id_field, db::last_save_id_field});
                        db::value_vector_t const params{next_save_id, next_save_id};
                        if (auto ul = unless(db.execute_update(sql, params))) {
                            state = db::make_error_result(error_type::update_info_failed, std::move(ul.value.error()));
                        }
                    }

                    if (state) {
                        db::commit(db);
                    } else {
                        db::rollback(db);
                        saved_datas.clear();
                    }
                } else {
                    state =
                        db::make_error_result(error_type::begin_transaction_failed, std::move(begin_result.error()));
                }
            }

            if (state) {
                if (auto const select_result = db::select_db_info(db)) {
                    db_info = std::move(select_result.value());
                } else {
                    state = db::make_error_result(error_type::select_info_failed, std::move(select_result.error()));
                }
            }

            completion(std::move(state), std::move(saved_datas), std::move(db_info));
        },
                      std::move(option));
    }

    // バックグラウンドでリバートする
    void execute_revert(db::manager::revert_preparation_f preparation,
                        std::function<void(db::manager::result_t &&state, db::object_data_vector_map_t &&reverted_datas,
                                           db::value_map_t &&db_info)> &&completion,
                        operation_option_t &&option) {
        this->execute(
            [preparation = std::move(preparation), completion = std::move(completion),
             manager = cast<db::manager>()](operation const &) mutable {
                db::integer::type rev_save_id;

                auto preparation_on_main = [&rev_save_id, &preparation]() { rev_save_id = preparation(); };

                dispatch_sync(manager.dispatch_queue(), std::move(preparation_on_main));

                auto &db = manager.database();

                db::manager::result_t state{nullptr};

                db::value_map_vector_map_t reverted_attrs;
                db::object_data_vector_map_t reverted_datas;
                db::value_map_t db_info;

                if (auto begin_result = db::begin_transaction(db)) {
                    db::integer::type last_save_id = 0;
                    db::integer::type current_save_id = 0;

                    if (auto select_result = db::select_db_info(db)) {
                        auto const &db_info = select_result.value();
                        if (db_info.count(db::current_save_id_field) > 0) {
                            current_save_id = db_info.at(db::current_save_id_field).get<db::integer>();
                        }
                        if (db_info.count(db::last_save_id_field) > 0) {
                            last_save_id = db_info.at(db::last_save_id_field).get<db::integer>();
                        }
                    } else {
                        state = db::make_error_result(error_type::select_info_failed, std::move(select_result.error()));
                    }

                    auto const &entity_models = manager.model().entities();

                    if (rev_save_id == current_save_id || last_save_id < rev_save_id) {
                        state = db::make_error_result(error_type::out_of_range_save_id);
                    } else {
                        for (auto const &entity_model_pair : entity_models) {
                            auto const &entity_name = entity_model_pair.first;
                            if (auto select_result = db::select_revert(db, entity_name, rev_save_id, current_save_id)) {
                                reverted_attrs.emplace(std::make_pair(entity_name, std::move(select_result.value())));
                            } else {
                                reverted_attrs.clear();
                                state = db::make_error_result(error_type::select_revert_failed,
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

                            if (auto obj_datas_result =
                                    db::make_entity_object_datas(db, entity_name, rel_models, entity_attrs)) {
                                reverted_datas.emplace(
                                    std::make_pair(entity_name, std::move(obj_datas_result.value())));
                            } else {
                                reverted_attrs.clear();
                                reverted_datas.clear();
                                state = db::make_error_result(error_type::fetch_object_datas_failed,
                                                              std::move(obj_datas_result.error()));
                                break;
                            }
                        }
                    }

                    if (state) {
                        db::value const save_id{rev_save_id};
                        auto const sql = update_sql(db::info_table, {db::current_save_id_field});
                        if (auto update_result = db.execute_update(sql, {save_id})) {
                            if (auto select_result = db::select_db_info(db)) {
                                db_info = std::move(select_result.value());
                            } else {
                                state = db::make_error_result(error_type::select_info_failed,
                                                              std::move(select_result.error()));
                            }
                        } else {
                            state = db::make_error_result(error_type::update_save_id_failed,
                                                          std::move(update_result.error()));
                        }
                    }

                    if (state) {
                        db::commit(db);
                    } else {
                        db::rollback(db);
                        reverted_datas.clear();
                    }
                } else {
                    state =
                        db::make_error_result(error_type::begin_transaction_failed, std::move(begin_result.error()));
                }

                completion(std::move(state), std::move(reverted_datas), std::move(db_info));
            },
            std::move(option));
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
    auto &db_info = impl_ptr<impl>()->_db_info;
    if (db_info.count(db::current_save_id_field) > 0) {
        return db_info.at(db::current_save_id_field);
    }
    return db::value::null_value();
}

db::value const &db::manager::last_save_id() const {
    auto &db_info = impl_ptr<impl>()->_db_info;
    if (db_info.count(db::last_save_id_field) > 0) {
        return db_info.at(db::last_save_id_field);
    }
    return db::value::null_value();
}

dispatch_queue_t db::manager::dispatch_queue() const {
    return impl_ptr<impl>()->_dispatch_queue;
}

db::object db::manager::insert_object(std::string const entity_name) {
    return impl_ptr<impl>()->insert_object(entity_name);
}

void db::manager::setup(db::manager::completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](db::manager::result_t && state,
                                                                                 db::value_map_t && db_info) mutable {
        auto lambda = [
            manager, state = std::move(state), db_info = std::move(db_info), completion = std::move(completion)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
            }
            completion(std::move(state));
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_setup(std::move(impl_completion), std::move(option));
}

void db::manager::clear(db::manager::completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](db::manager::result_t && state,
                                                                                 db::value_map_t && db_info) {
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
    auto impl_completion = [completion = std::move(completion), manager = *this](db::manager::result_t && state,
                                                                                 db::value_map_t && db_info) {
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
        db::manager::result_t && state, db::object_data_vector_map_t && fetched_datas) {
        auto lambda = [
            manager, completion = std::move(completion), state = std::move(state),
            fetched_datas = std::move(fetched_datas)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->load_map_object_datas(fetched_datas, true);
                manager.impl_ptr<impl>()->erase_changed_objects(fetched_datas);
                manager.impl_ptr<impl>()->_inserted_objects.clear();
                completion(db::manager::result_t{nullptr});
            } else {
                completion(db::manager::result_t{std::move(state.error())});
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
    auto impl_preparation = [preparation = std::move(preparation)]() {
        auto counts = preparation();
        db::value_map_vector_map_t values{};

        for (auto &count_pair : counts) {
            values.emplace(std::make_pair(count_pair.first, db::value_map_vector_t{count_pair.second}));
        }

        return values;
    };

    insert_objects(std::move(impl_preparation), std::move(completion), std::move(option));
}

void db::manager::insert_objects(db::manager::insert_preparation_values_f preparation,
                                 db::manager::vector_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager::result_t && state, db::object_data_vector_map_t && inserted_datas, db::value_map_t && db_info) {
        auto lambda = [
            state = std::move(state), inserted_datas = std::move(inserted_datas), manager,
            completion = std::move(completion), db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects = manager.impl_ptr<impl>()->load_vector_object_datas(inserted_datas, false, false);
                completion(db::manager::vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager::vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_insert(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::fetch_objects(db::manager::fetch_preparation_option_f preparation,
                                db::manager::vector_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager::result_t && state, db::object_data_vector_map_t && fetched_datas) {
        auto lambda = [
            state = std::move(state), completion = std::move(completion), fetched_datas = std::move(fetched_datas),
            manager
        ]() mutable {
            if (state) {
                auto loaded_objects = manager.impl_ptr<impl>()->load_vector_object_datas(fetched_datas, false, false);
                completion(db::manager::vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager::vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::fetch_const_objects(db::manager::fetch_preparation_option_f preparation,
                                      db::manager::const_vector_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager::result_t && state, db::object_data_vector_map_t && fetched_datas) {
        auto lambda = [
            state = std::move(state), completion = std::move(completion), fetched_datas = std::move(fetched_datas),
            manager
        ]() mutable {
            if (state) {
                completion(
                    db::manager::const_vector_result_t{db::to_const_vector_objects(manager.model(), fetched_datas)});
            } else {
                completion(db::manager::const_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::fetch_objects(db::manager::fetch_preparation_ids_f preparation,
                                db::manager::map_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager::result_t && state, db::object_data_vector_map_t && fetched_datas) {
        auto lambda = [
            manager, completion = std::move(completion), state = std::move(state),
            fetched_datas = std::move(fetched_datas)
        ]() mutable {
            if (state) {
                auto loaded_objects = manager.impl_ptr<impl>()->load_map_object_datas(fetched_datas, false);
                completion(db::manager::map_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager::map_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::fetch_const_objects(db::manager::fetch_preparation_ids_f preparation,
                                      db::manager::const_map_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager::result_t && state, db::object_data_vector_map_t && fetched_datas) {
        auto lambda = [
            manager, completion = std::move(completion), state = std::move(state),
            fetched_datas = std::move(fetched_datas)
        ]() mutable {
            if (state) {
                completion(db::manager::const_map_result_t{db::to_const_map_objects(manager.model(), fetched_datas)});
            } else {
                completion(db::manager::const_map_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), std::move(option));
}

void db::manager::save(db::manager::vector_completion_f completion, operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager::result_t && state, db::object_data_vector_map_t && saved_datas, db::value_map_t && db_info) {
        auto lambda = [
            manager, state = std::move(state), completion = std::move(completion), saved_datas = std::move(saved_datas),
            db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects = manager.impl_ptr<impl>()->load_vector_object_datas(saved_datas, false, true);
                manager.impl_ptr<impl>()->erase_changed_objects(saved_datas);
                completion(db::manager::vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager::vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(manager.dispatch_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_save(std::move(impl_completion), std::move(option));
}

void db::manager::revert(db::manager::revert_preparation_f preparation, db::manager::vector_completion_f completion,
                         operation_option_t option) {
    auto impl_completion = [completion = std::move(completion), manager = *this](
        db::manager::result_t && state, db::object_data_vector_map_t && reverted_datas, db::value_map_t && db_info) {
        auto lambda = [
            manager, state = std::move(state), completion = std::move(completion),
            reverted_datas = std::move(reverted_datas), db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects = manager.impl_ptr<impl>()->load_vector_object_datas(reverted_datas, false, false);
                completion(db::manager::vector_result_t{std::move(loaded_objects)});
            } else {
                completion(db::manager::vector_result_t{std::move(state.error())});
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

std::string yas::to_string(db::manager::error_type const &error) {
    switch (error) {
        case db::manager::error_type::begin_transaction_failed:
            return "begin_transaction_failed";
        case db::manager::error_type::vacuum_failed:
            return "vacuum_failed";
        case db::manager::error_type::select_info_failed:
            return "select_info_failed";
        case db::manager::error_type::update_info_failed:
            return "update_info_failed";
        case db::manager::error_type::version_not_found:
            return "version_not_found";
        case db::manager::error_type::invalid_version_text:
            return "invalid_version_text";
        case db::manager::error_type::alter_entity_table_failed:
            return "alter_entity_table_failed";
        case db::manager::error_type::create_info_table_failed:
            return "create_info_table_failed";
        case db::manager::error_type::insert_info_failed:
            return "insert_info_failed";
        case db::manager::error_type::create_entity_table_failed:
            return "create_entity_table_failed";
        case db::manager::error_type::create_relation_table_failed:
            return "create_relation_table_failed";
        case db::manager::error_type::create_index_failed:
            return "create_index_failed";
        case db::manager::error_type::insert_attributes_failed:
            return "insert_attributes_failed";
        case db::manager::error_type::insert_relation_failed:
            return "insert_relation_failed";
        case db::manager::error_type::save_id_not_found:
            return "save_id_not_found";
        case db::manager::error_type::update_save_id_failed:
            return "update_save_id_failed";
        case db::manager::error_type::delete_failed:
            return "delete_failed";
        case db::manager::error_type::purge_failed:
            return "purge_failed";
        case db::manager::error_type::purge_relation_failed:
            return "purge_relation_failed";
        case db::manager::error_type::select_last_failed:
            return "select_last_failed";
        case db::manager::error_type::select_revert_failed:
            return "select_revert_failed";
        case db::manager::error_type::fetch_object_datas_failed:
            return "fetch_object_datas_failed";
        case db::manager::error_type::out_of_range_save_id:
            return "out_of_range_save_id";
        case db::manager::error_type::select_failed:
            return "select_failed";
        case db::manager::error_type::last_insert_rowid_failed:
            return "last_insert_rowid_failed";
        case db::manager::error_type::none:
            return "none";
    }
    return std::string();
}
