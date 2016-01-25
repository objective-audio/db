//
//  yas_db_manager.cpp
//

#include <dispatch/dispatch.h>
#include "yas_db_attribute.h"
#include "yas_db_entity.h"
#include "yas_db_manager.h"
#include "yas_db_model.h"
#include "yas_db_relation.h"
#include "yas_db_select_option.h"
#include "yas_db_sql_utils.h"
#include "yas_db_utils.h"
#include "yas_each_index.h"
#include "yas_operation.h"
#include "yas_version.h"

using namespace yas;

#pragma mark - error

template <typename T>
db::manager::error<T>::error(std::nullptr_t) : _type(), _db_error(nullptr) {
}

template <typename T>
db::manager::error<T>::error(T const &error_type, db::error const &db_error) : _type(error_type), _db_error(db_error) {
}

template <typename T>
db::manager::error<T>::operator bool() const {
    return _type != T::none;
}

template <typename T>
T const &db::manager::error<T>::type() const {
    return _type;
}

template <typename T>
db::error const &db::manager::error<T>::database_error() const {
    return _db_error;
}

template struct db::manager::error<db::manager::setup_error_type>;
template struct db::manager::error<db::manager::insert_error_type>;
template struct db::manager::error<db::manager::save_error_type>;

#pragma mark - impl

struct db::manager::impl : public base::impl {
    db::database database;
    db::model model;
    operation_queue queue;
    db::weak_object_map_map cached_objects;
    db::object_map_map changed_objects;
    db::value_map db_info;

    impl(std::string const &path, db::model const &model) : database(path), model(model), queue(), cached_objects() {
    }

    db::object load_object_data(std::string const &entity_name, db::object_data const &data) {
        if (cached_objects.count(entity_name) == 0) {
            cached_objects.emplace(std::make_pair(entity_name, weak_object_map{}));
        }

        auto manager = cast<db::manager>();
        auto &objects = cached_objects.at(entity_name);

        if (data.attributes.count(object_id_field)) {
            if (auto const &object_id_value = data.attributes.at(object_id_field)) {
                auto const &object_id = object_id_value.get<integer>();

                db::object object{nullptr};

                if (objects.count(object_id) > 0) {
                    if (auto const &weak_object = objects.at(object_id)) {
                        object = weak_object.lock();
                        if (!object) {
                            throw "cached object is released. entity_name (" + entity_name + ") object_id (" +
                                std::to_string(object_id) + ")";
                            ;
                        }
                    }
                }

                if (!object) {
                    object = db::object{manager, model, entity_name};
                    objects.emplace(std::make_pair(object_id, to_weak(object)));
                }

                object.load_data(data);

                return object;
            }
        } else {
            throw "object_id not found.";
        }

        return db::object::empty();
    }

    object_vector_map load_object_datas(object_data_vector_map const &datas) {
        object_vector_map loaded_objects;
        for (auto const &entity_pair : datas) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_datas = entity_pair.second;

            object_vector objects;
            objects.reserve(entity_datas.size());

            for (auto const &data : entity_datas) {
                if (auto const obj = load_object_data(entity_name, data)) {
                    objects.emplace_back(std::move(obj));
                }
            }

            loaded_objects.emplace(std::make_pair(entity_name, std::move(objects)));
        }
        return loaded_objects;
    }

    void set_db_info(db::value_map const &info) {
        db_info = info;
    }

    db::object_data_vector_map changed_datas_for_save() {
        db::object_data_vector_map changed_datas;
        for (auto const &entity_pair : changed_objects) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_objects = entity_pair.second;

            db::object_data_vector entity_datas;
            entity_datas.reserve(entity_objects.size());

            for (auto const &object_pair : entity_objects) {
                auto object = object_pair.second;
                auto data = object.data_for_save();
                if (data.attributes.size() > 0) {
                    entity_datas.emplace_back(std::move(data));
                } else {
                    throw "object_data.attributes is empty.";
                }
                if (auto manageable_object = dynamic_cast<manageable *>(&object)) {
                    manageable_object->set_status(db::object_status::updating);
                }
            }

            if (entity_datas.size() > 0) {
                changed_datas.emplace(std::make_pair(entity_name, std::move(entity_datas)));
            }
        }
        return changed_datas;
    }

    db::object cached_object(std::string const &entity_name, db::integer::type object_id) {
        if (cached_objects.count(entity_name) > 0) {
            auto &entity_objects = cached_objects.at(entity_name);
            if (entity_objects.count(object_id)) {
                if (auto const &weak_object = entity_objects.at(object_id)) {
                    if (auto object = weak_object.lock()) {
                        return object;
                    }
                }
            }
        }
        return db::object::empty();
    }

    void _object_did_change(db::object const &object) {
        auto const &entity_name = object.entity_name();
        if (changed_objects.count(entity_name) == 0) {
            changed_objects.insert(std::make_pair(entity_name, db::object_map{}));
        }

        changed_objects.at(entity_name).emplace(std::make_pair(object.object_id().get<integer>(), object));
    }

    void _object_did_erase(std::string const &entity_name, db::integer::type const object_id) {
        if (cached_objects.count(entity_name) > 0) {
            auto &objects = cached_objects.at(entity_name);
            if (objects.count(object_id)) {
                objects.erase(object_id);
            }
        }
    }
};

#pragma mark - manager

db::manager::manager(std::string const &db_path, db::model const &model)
    : super_class(std::make_unique<impl>(db_path, model)) {
}

db::manager::manager(std::nullptr_t) : super_class(nullptr) {
}

void db::manager::setup(setup_completion_f &&completion) {
    execute([completion = std::move(completion), model = impl_ptr<impl>()->model](db::manager & manager,
                                                                                  operation const &op) {
        auto &db = manager.database();

        db::value_map db_info;
        setup_result result{nullptr};

        if (db::begin_transaction(db)) {
            if (db::table_exists(db, info_table)) {
                auto select_result =
                    db::select(db, {info_table}, {.fields = {version_field}, .limit_range = db::range{0, 1}});
                if (select_result) {
                    auto const update_result = db.execute_update(update_sql(info_table, {version_field}, ""),
                                                                 {db::value{model.version().str()}});
                    if (!update_result) {
                        result = setup_result{make_error(setup_error_type::update_info_failed, update_result.error())};
                    }
                } else {
                    result = setup_result{make_error(setup_error_type::select_info_failed, select_result.error())};
                }

                bool needs_migration = false;

                if (result) {
                    auto const &infos = select_result.value();
                    auto const &info = *infos.rbegin();
                    if (info.count(version_field) == 0) {
                        result = setup_result{make_error(setup_error_type::version_not_found)};
                    } else {
                        auto db_version_str = info.at(version_field).get<text>();
                        if (db_version_str.size() == 0) {
                            result = setup_result{make_error(setup_error_type::invalid_version_text)};
                        } else {
                            auto const db_version = yas::version{db_version_str};
                            if (db_version < model.version()) {
                                needs_migration = true;
                            }
                        }
                    }
                }

                if (result && needs_migration) {
                    for (auto const &entity_pair : model.entities()) {
                        auto const &entity_name = entity_pair.first;
                        auto const &entity = entity_pair.second;

                        if (db::table_exists(db, entity_name)) {
                            // alter table
                            for (auto const &attr_pair : entity.attributes) {
                                if (!db::column_exists(db, attr_pair.first, entity_name)) {
                                    auto const &attr = attr_pair.second;
                                    if (!db.execute_update(alter_table_sql(entity_name, attr.sql()))) {
                                        result = setup_result{make_error(setup_error_type::alter_entity_table_failed)};
                                        break;
                                    }
                                }
                            }
                        } else {
                            // create table
                            auto const update_result = db.execute_update(entity.sql_for_create());
                            if (!update_result) {
                                result = setup_result{
                                    make_error(setup_error_type::create_entity_table_failed, update_result.error())};
                                break;
                            }
                        }

                        if (!result) {
                            break;
                        }

                        for (auto &rel_pair : entity.relations) {
                            auto &relation = rel_pair.second;
                            auto const update_result = db.execute_update(relation.sql_for_create());
                            if (!update_result) {
                                result = setup_result{
                                    make_error(setup_error_type::create_relation_table_failed, update_result.error())};
                                break;
                            }
                        }

                        if (!result) {
                            break;
                        }
                    }
                }
            } else {
                // create information table

                auto const update_result = db.execute_update(
                    db::create_table_sql(info_table, {version_field, current_save_id_field, last_save_id_field}));
                if (!update_result) {
                    result =
                        setup_result{make_error(setup_error_type::create_info_table_failed, update_result.error())};
                }

                if (result) {
                    db::value_map args{std::make_pair(version_field, db::value{model.version().str()})};
                    auto const update_result = db.execute_update(db::insert_sql(info_table, {version_field}), args);
                    if (!update_result) {
                        result = setup_result{make_error(setup_error_type::insert_info_failed, update_result.error())};
                    }
                }

                // create entity tables

                if (result) {
                    auto const &entities = model.entities();
                    for (auto &entity_pair : entities) {
                        auto &entity = entity_pair.second;
                        auto const update_result = db.execute_update(entity.sql_for_create());
                        if (!update_result) {
                            result = setup_result{
                                make_error(setup_error_type::create_entity_table_failed, update_result.error())};
                            break;
                        }

                        for (auto &rel_pair : entity.relations) {
                            auto &relation = rel_pair.second;
                            auto const update_result = db.execute_update(relation.sql_for_create());
                            if (!update_result) {
                                result = setup_result{
                                    make_error(setup_error_type::create_relation_table_failed, update_result.error())};
                                break;
                            }
                        }

                        if (!result) {
                            break;
                        }
                    }
                }
            }
        } else {
            result = setup_result{make_error(setup_error_type::begin_transaction_failed)};
        }

        if (result) {
            if (auto const &select_result = select_db_info(db)) {
                db_info = std::move(select_result.value());
            }
        }

        if (result) {
            db::commit(db);
        } else {
            db::rollback(db);
        }

        auto lambda = [
            completion = std::move(completion),
            result = std::move(result),
            manager,
            db_info = std::move(db_info)
        ]() mutable {
            if (result) {
                manager.impl_ptr<impl>()->set_db_info(db_info);
            }

            completion(manager, result);
        };

        dispatch_async(dispatch_get_main_queue(), std::move(lambda));
    });
}

std::string const &db::manager::database_path() const {
    return impl_ptr<impl>()->database.database_path();
}

db::database const &db::manager::database() const {
    return impl_ptr<impl>()->database;
}

db::database &db::manager::database() {
    return impl_ptr<impl>()->database;
}

db::model const &db::manager::model() const {
    return impl_ptr<impl>()->model;
}

db::integer::type db::manager::current_save_id() const {
    auto &db_info = impl_ptr<impl>()->db_info;
    if (db_info.count(current_save_id_field)) {
        return db_info.at(current_save_id_field).get<integer>();
    }
    return 0;
}

db::integer::type db::manager::last_save_id() const {
    auto &db_info = impl_ptr<impl>()->db_info;
    if (db_info.count(last_save_id_field)) {
        return db_info.at(last_save_id_field).get<integer>();
    }
    return 0;
}

void db::manager::execute(execution_f &&db_execution) {
    auto execution = [db_execution = std::move(db_execution), manager = *this](operation const &op) mutable {
        if (!op.is_canceled()) {
            auto &db = manager.impl_ptr<impl>()->database;
            db.open();
            db_execution(manager, op);
            db.close();
        }
    };

    impl_ptr<impl>()->queue.add_operation(operation{std::move(execution)});
}

void db::manager::insert_objects(entity_count_map const &counts, insert_completion_f &&completion) {
    execute(
        [completion = std::move(completion), counts = std::move(counts)](db::manager & manager, operation const &op) {
            auto &db = manager.database();

            db::value_map db_info;
            object_data_vector_map inserted_datas;
            db::integer::type start_obj_id = 1;

            using insert_state = result<std::nullptr_t, error<insert_error_type>>;
            insert_state state{nullptr};

            db::begin_transaction(db);

            db::integer::type next_save_id = 0;
            if (auto const &select_result = db::select_db_info(db)) {
                auto const &db_info = select_result.value();
                if (db_info.count(current_save_id_field)) {
                    next_save_id = db_info.at(current_save_id_field).get<integer>() + 1;
                }
            }

            if (next_save_id == 0) {
                state = insert_state{make_error(insert_error_type::save_id_not_found)};
            }

            db::value const save_id_value{next_save_id};

            for (auto const &count_pair : counts) {
                auto const &entity_name = count_pair.first;
                auto const &count = count_pair.second;

                if (auto max_value = db::max(db, entity_name, object_id_field)) {
                    start_obj_id = max_value.get<integer>() + 1;
                }

                for (auto const &idx : each_index<std::size_t>{count}) {
                    db::value obj_id_value{start_obj_id + idx};

                    if (!db.execute_update(db::insert_sql(entity_name, {object_id_field, save_id_field}),
                                           db::value_vector{obj_id_value, save_id_value})) {
                        state = insert_state{make_error(insert_error_type::insert_failed)};
                        break;
                    }

                    auto const &select_result =
                        db::select(db, entity_name, {.where_exprs = db::equal_field_expr(object_id_field),
                                                     .arguments = {{std::make_pair(object_id_field, obj_id_value)}}});
                    if (!select_result) {
                        state = insert_state{make_error(insert_error_type::select_failed)};
                        break;
                    }

                    if (inserted_datas.count(entity_name) == 0) {
                        object_data_vector entity_datas{};
                        entity_datas.reserve(count);
                        inserted_datas.emplace(std::make_pair(entity_name, std::move(entity_datas)));
                    }

                    inserted_datas.at(entity_name)
                        .emplace_back(object_data{.attributes = std::move(select_result.value().at(0))});
                }
            }

            if (state) {
                auto const sql = update_sql(info_table, {current_save_id_field, last_save_id_field}, "");
                db::value_vector const params{save_id_value, save_id_value};
                auto update_result = db.execute_update(sql, params);
                if (update_result) {
                    auto const select_result = db::select_db_info(db);
                    if (select_result) {
                        db_info = select_result.value();
                    } else {
                        state = insert_state{make_error(insert_error_type::save_id_not_found, select_result.error())};
                    }
                } else {
                    state = insert_state{make_error(insert_error_type::update_save_id_failed, update_result.error())};
                }
            }

            if (state) {
                db::commit(db);
            } else {
                db::rollback(db);
                inserted_datas.clear();
            }

            auto lambda = [
                state = std::move(state),
                inserted_datas = std::move(inserted_datas),
                manager,
                completion = std::move(completion),
                db_info = std::move(db_info)
            ]() mutable {
                if (state) {
                    manager.impl_ptr<impl>()->set_db_info(db_info);
                    auto loaded_objects = manager.impl_ptr<impl>()->load_object_datas(inserted_datas);
                    completion(manager, insert_result{std::move(loaded_objects)});
                } else {
                    completion(manager, insert_result{state.error()});
                }
            };

            dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
        });
}

namespace yas {
namespace db {
    using object_data_result = result<db::object_data, manager::error<manager::fetch_error_type>>;

    object_data_result fetch_object_data(database &db, relation_map const &relation_models, db::value_map &attributes) {
        db::value_vector_map relations;

        for (auto const &rel_model_pair : relation_models) {
            auto const &rel_name = rel_model_pair.first;
            auto const &table_name = rel_model_pair.second.table_name;
            std::string where_exprs =
                joined({equal_field_expr(save_id_field), equal_field_expr(src_id_field)}, " and ");
            db::select_option option{.where_exprs = where_exprs,
                                     .arguments = {{save_id_field, attributes.at(save_id_field)},
                                                   {src_id_field, attributes.at(object_id_field)}}};

            auto const select_result = db::select(db, table_name, std::move(option));
            if (select_result) {
                auto const &result_relations = select_result.value();
                db::value_vector rels;
                rels.reserve(result_relations.size());
                for (auto const &result_relation : result_relations) {
                    rels.push_back(result_relation.at(tgt_id_field));
                }
                relations.emplace(std::make_pair(rel_name, std::move(rels)));
            } else {
                return object_data_result{make_error(manager::fetch_error_type::select_failed, select_result.error())};
            }
        }

        return object_data_result{object_data{.attributes = std::move(attributes), .relations = std::move(relations)}};
    }
}
}

void db::manager::fetch_objects(std::string const &entity_name, db::select_option &&option,
                                fetch_completion_f &&completion) {
    execute([entity_name, option = std::move(option), completion = std::move(completion)](db::manager & manager,
                                                                                          operation const &) {
        auto &db = manager.database();

        auto const &rel_models = manager.model().entities().at(entity_name).relations;
        using fetch_state = result<std::nullptr_t, error<fetch_error_type>>;
        fetch_state state{nullptr};

        object_data_vector_map fetched_datas;

        auto begin_result = db::begin_transaction(db);
        if (begin_result) {
            auto select_result = db::select_last(db, entity_name, nullptr, option);
            if (select_result) {
                db::object_data_vector entity_datas;
                entity_datas.reserve(select_result.value().size());

                for (value_map &attributes : select_result.value()) {
                    auto object_data_result = fetch_object_data(db, rel_models, attributes);
                    if (object_data_result) {
                        entity_datas.emplace_back(std::move(object_data_result.value()));
                    } else {
                        state = fetch_state{object_data_result.error()};
                    }
                }

                fetched_datas.emplace(std::make_pair(entity_name, std::move(entity_datas)));
            } else {
                state = fetch_state{make_error(fetch_error_type::select_failed, select_result.error())};
            }

            if (state) {
                db::commit(db);
            } else {
                db::rollback(db);
                fetched_datas.clear();
            }
        } else {
            state = fetch_state{make_error(fetch_error_type::begin_failed, begin_result.error())};
        }

        auto lambda = [
            state = std::move(state),
            completion = std::move(completion),
            fetched_datas = std::move(fetched_datas),
            manager
        ]() mutable {
            if (state) {
                auto loaded_objects = manager.impl_ptr<impl>()->load_object_datas(fetched_datas);
                completion(manager, fetch_result{std::move(loaded_objects)});
            } else {
                completion(manager, fetch_result{state.error()});
            }
        };
        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    });
}

void db::manager::fetch_relation_objects(object_vector_map const &objects, fetch_completion_f &&completion) {
    auto rel_ids = db::relation_ids(objects);

    execute([completion = std::move(completion), rel_ids = std::move(rel_ids)](manager & manager, operation const &) {
        auto &db = manager.database();

        using fetch_state = result<std::nullptr_t, error<fetch_error_type>>;
        fetch_state state{nullptr};

        object_data_vector_map fetched_datas;

        auto begin_result = db::begin_transaction(db);
        if (begin_result) {
            for (auto const &entity_pair : rel_ids) {
                auto const &entity_name = entity_pair.first;
                auto const &rel_models = manager.model().entities().at(entity_name).relations;

                auto const &entity_rel_ids = entity_pair.second;
                db::select_option option{
                    .where_exprs =
                        object_id_field + " in (" +
                        joined(entity_rel_ids, ",", [](auto const &rel_id) { return std::to_string(rel_id); }) + ")"};

                auto select_result = db::select_last(db, entity_name, nullptr, option);
                if (select_result) {
                    db::object_data_vector entity_datas;
                    entity_datas.reserve(select_result.value().size());

                    for (value_map &attributes : select_result.value()) {
                        auto object_data_result = fetch_object_data(db, rel_models, attributes);
                        if (object_data_result) {
                            entity_datas.emplace_back(std::move(object_data_result.value()));
                        } else {
                            state = fetch_state{object_data_result.error()};
                        }
                    }

                    fetched_datas.emplace(std::make_pair(entity_name, std::move(entity_datas)));
                } else {
                    state = fetch_state{make_error(fetch_error_type::select_failed, select_result.error())};
                }
            }
        } else {
            state = fetch_state{make_error(fetch_error_type::begin_failed, begin_result.error())};
        }

        auto lambda = [
            manager,
            completion = std::move(completion),
            state = std::move(state),
            fetched_datas = std::move(fetched_datas)
        ]() mutable {
            if (state) {
                auto loaded_objects = manager.impl_ptr<impl>()->load_object_datas(fetched_datas);
                completion(manager, fetch_result{std::move(loaded_objects)});
            } else {
                completion(manager, fetch_result{state.error()});
            }
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    });
}

void db::manager::save(save_completion_f &&completion) {
    auto const changed_datas = impl_ptr<impl>()->changed_datas_for_save();

    execute([completion = std::move(completion), changed_datas = std::move(changed_datas)](manager & manager,
                                                                                           operation const &) {
        auto &db = manager.database();

        db::value_map db_info;
        db::object_data_vector_map saved_datas;

        using save_state = result<std::nullptr_t, error<save_error_type>>;
        save_state state{nullptr};

        if (changed_datas.size() > 0) {
            db::begin_transaction(db);

            db::integer::type next_save_id = 0;
            if (auto const select_result = db::select_db_info(db)) {
                auto const &db_info = select_result.value();
                if (db_info.count(current_save_id_field)) {
                    next_save_id = db_info.at(current_save_id_field).get<integer>() + 1;
                }
            }

            if (next_save_id == 0) {
                state = save_state{make_error(save_error_type::save_id_not_found)};
            } else {
                auto const &save_id_pair = std::make_pair(save_id_field, db::value{next_save_id});

                for (auto const &entity_pair : changed_datas) {
                    auto const &entity_name = entity_pair.first;
                    auto const &changed_entity_datas = entity_pair.second;
                    auto const sql = manager.model().entities().at(entity_name).sql_for_insert();
                    auto const &relation_models = manager.model().entities().at(entity_name).relations;

                    db::object_data_vector entity_saved_datas;

                    for (auto data : changed_entity_datas) {
                        if (data.attributes.count(save_id_field)) {
                            data.attributes.erase(save_id_field);
                        }
                        if (data.attributes.count(id_field)) {
                            data.attributes.erase(id_field);
                        }
                        data.attributes.insert(save_id_pair);

                        auto const update_result = db.execute_update(sql, data.attributes);
                        if (!update_result) {
                            state = save_state{make_error(save_error_type::insert_failed, update_result.error())};
                        }

                        if (state) {
                            auto const src_id_pair = std::make_pair(src_id_field, data.attributes.at(object_id_field));

                            for (auto const &rel_pair : data.relations) {
                                auto const &rel_name = rel_pair.first;
                                auto const &rel = rel_pair.second;
                                auto const &rel_model = relation_models.at(rel_name);
                                auto const &sql = rel_model.sql_for_insert();

                                for (auto const &rel_tgt_id : rel) {
                                    auto const tgt_id_pair = std::make_pair(tgt_id_field, rel_tgt_id);
                                    auto const update_result = db.execute_update(
                                        sql, db::value_map{src_id_pair, std::move(tgt_id_pair), save_id_pair});
                                    if (!update_result) {
                                        state = save_state{make_error(save_error_type::insert_failed)};
                                        break;
                                    }
                                }
                            }
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
                db::value const save_id{next_save_id};
                auto const sql = update_sql(info_table, {current_save_id_field, last_save_id_field}, "");
                db::value_vector const params{save_id, save_id};
                auto update_result = db.execute_update(sql, params);
                if (!update_result) {
                    state = save_state{make_error(save_error_type::update_save_id_failed, update_result.error())};
                }
            }

            if (state) {
                db::commit(db);
            } else {
                db::rollback(db);
                saved_datas.clear();
            }
        }

        if (state) {
            if (auto const select_result = db::select_db_info(db)) {
                db_info = std::move(select_result.value());
            } else {
                state = save_state{make_error(save_error_type::save_id_not_found)};
            }
        }

        auto lambda = [
            manager,
            state = std::move(state),
            completion = std::move(completion),
            saved_datas = std::move(saved_datas),
            db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(db_info);
                auto loaded_objects = manager.impl_ptr<impl>()->load_object_datas(saved_datas);
                manager.impl_ptr<impl>()->changed_objects.clear();
                completion(manager, save_result{std::move(loaded_objects)});
            } else {
                completion(manager, save_result{state.error()});
            }
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    });
}

db::object db::manager::cached_object(std::string const &entity_name, db::integer::type const object_id) const {
    return impl_ptr<impl>()->cached_object(entity_name, object_id);
}

void db::manager::_object_did_change(db::object const &object) {
    impl_ptr<impl>()->_object_did_change(object);
}

void db::manager::_object_did_erase(std::string const &entity_name, db::integer::type const object_id) {
    impl_ptr<impl>()->_object_did_erase(entity_name, object_id);
}

std::string yas::to_string(db::manager::setup_error_type const &error) {
    switch (error) {
        case db::manager::setup_error_type::begin_transaction_failed:
            return "begin_transaction_failed";
        case db::manager::setup_error_type::select_info_failed:
            return "select_info_failed";
        case db::manager::setup_error_type::update_info_failed:
            return "update_info_failed";
        case db::manager::setup_error_type::version_not_found:
            return "version_not_found";
        case db::manager::setup_error_type::invalid_version_text:
            return "invalid_version_text";
        case db::manager::setup_error_type::alter_entity_table_failed:
            return "alter_entity_table_failed";
        case db::manager::setup_error_type::create_info_table_failed:
            return "create_info_table_failed";
        case db::manager::setup_error_type::insert_info_failed:
            return "insert_info_failed";
        case db::manager::setup_error_type::create_entity_table_failed:
            return "create_entity_table_failed";
        case db::manager::setup_error_type::create_relation_table_failed:
            return "create_relation_table_failed";
        case db::manager::setup_error_type::none:
            return "none";
    }
    return std::string();
}

std::string yas::to_string(db::manager::insert_error_type const &error) {
    switch (error) {
        case db::manager::insert_error_type::insert_failed:
            return "insert_failed";
        case db::manager::insert_error_type::select_failed:
            return "select_failed";
        case db::manager::insert_error_type::save_id_not_found:
            return "save_id_not_found";
        case db::manager::insert_error_type::update_save_id_failed:
            return "update_save_id_failed";
        case db::manager::insert_error_type::none:
            return "none";
    }
    return std::string();
}

std::string yas::to_string(db::manager::save_error_type const &error) {
    switch (error) {
        case db::manager::save_error_type::save_id_not_found:
            return "save_id_not_found";
        case db::manager::save_error_type::update_save_id_failed:
            return "update_save_id_failed";
        case db::manager::save_error_type::insert_failed:
            return "insert_failed";
        case db::manager::save_error_type::none:
            return "none";
    }
    return std::string();
}
