//
//  yas_db_manager.cpp
//

#include <dispatch/dispatch.h>
#include "yas_db_manager.h"
#include "yas_db_order.h"
#include "yas_db_sql_utils.h"
#include "yas_db_utils.h"
#include "yas_each_index.h"

using namespace yas;

struct db::manager::impl : public base::impl {
    db::database database;
    db::model model;
    operation_queue queue;
    db::entity_objects_map entity_objects;
    db::column_map db_info;

    impl(std::string const &path, db::model const &model) : database(path), model(model), queue(), entity_objects() {
    }

    db::object const &load_object(std::string const &entity_name, db::column_map const &map) {
        if (entity_objects.count(entity_name) == 0) {
            entity_objects.emplace(std::make_pair(entity_name, object_map{}));
        }

        auto &objects = entity_objects.at(entity_name);

        if (auto const &object_id_value = map.at(object_id_field)) {
            auto const &object_id = object_id_value.get<integer>();
            if (objects.count(object_id) > 0) {
                objects.at(object_id).load(map);
            } else {
                db::object obj{model, entity_name};
                obj.load(map);
                objects.emplace(std::make_pair(object_id, std::move(obj)));
            }
            return objects.at(object_id);
        } else {
            throw "object_id not found.";
        }

        return db::object::empty();
    }

    std::vector<db::object> load_objects(column_maps_map const &entity_maps) {
        std::vector<db::object> objects;
        for (auto const &entity_pair : entity_maps) {
            auto const &entity_name = entity_pair.first;
            for (auto const &map : entity_pair.second) {
                if (auto const &obj = load_object(entity_name, map)) {
                    objects.push_back(obj);
                }
            }
        }
        return objects;
    }

    void set_db_info(db::column_map const &info) {
        db_info = info;
    }
};

db::manager::manager(std::string const &db_path, db::model const &model)
    : super_class(std::make_unique<impl>(db_path, model)) {
}

db::manager::manager(std::nullptr_t) : super_class(nullptr) {
}

void db::manager::setup(setup_completion_f &&completion) {
    execute([completion = std::move(completion), model = impl_ptr<impl>()->model, manager = *this](
        db::database & db, operation const &op) {
        db::column_map db_info;
        setup_result result{nullptr};

        if (db::begin_transaction(db)) {
            if (db::table_exists(db, info_table)) {
                auto select_result = db::select(db, {info_table}, {version_field, save_id_field}, "", {},
                                                {yas::db::field_order{version_field, yas::db::order::ascending}});
                if (select_result) {
                    if (!db.execute_update(update_sql(info_table, {version_field}, ""),
                                           {db::value{model.version().str()}})) {
                        result = setup_result{setup_error::update_info_failed};
                    }
                } else {
                    result = setup_result{setup_error::select_info_failed};
                }

                bool needs_migration = false;

                if (result) {
                    auto const &infos = select_result.value();
                    auto const &info = *infos.rbegin();
                    if (info.count(version_field) == 0) {
                        result = setup_result{setup_error::version_not_found};
                    } else {
                        auto db_version_str = info.at(version_field).get<text>();
                        if (db_version_str.size() == 0) {
                            result = setup_result{setup_error::invalid_version_text};
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
                                        result = setup_result{setup_error::alter_entity_table_failed};
                                        break;
                                    }
                                }
                            }
                        } else {
                            // create table
                            if (!db.execute_update(entity.sql_for_create())) {
                                result = setup_result{setup_error::create_entity_table_failed};
                                break;
                            }
                        }

                        if (!result) {
                            break;
                        }

                        for (auto &rel_pair : entity.relations) {
                            auto &relation = rel_pair.second;
                            if (!db.execute_update(relation.sql())) {
                                result = setup_result{setup_error::create_relation_table_failed};
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

                if (!db.execute_update(db::create_table_sql(info_table, {version_field, save_id_field}))) {
                    result = setup_result{setup_error::create_info_table_failed};
                }

                if (result) {
                    db::column_map args{std::make_pair(version_field, db::value{model.version().str()})};
                    if (!db.execute_update(db::insert_sql(info_table, {version_field}), args)) {
                        result = setup_result{setup_error::insert_info_failed};
                    }
                }

                // create entity tables

                if (result) {
                    auto const &entities = model.entities();
                    for (auto &entity_pair : entities) {
                        auto &entity = entity_pair.second;
                        if (!db.execute_update(entity.sql_for_create())) {
                            result = setup_result{setup_error::create_entity_table_failed};
                            break;
                        }

                        for (auto &rel_pair : entity.relations) {
                            auto &relation = rel_pair.second;
                            if (!db.execute_update(relation.sql())) {
                                result = setup_result{setup_error::create_relation_table_failed};
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
            result = setup_result{setup_error::begin_transaction_failed};
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

        auto lambda =
            [completion = std::move(completion), result = std::move(result), manager, db_info = std::move(db_info)]() {
            if (result) {
                manager.impl_ptr<impl>()->set_db_info(db_info);
            }

            completion(result);
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

db::model const &db::manager::model() const {
    return impl_ptr<impl>()->model;
}

db::integer::type db::manager::save_id() const {
    auto &db_info = impl_ptr<impl>()->db_info;
    if (db_info.count(save_id_field)) {
        return db_info.at(save_id_field).get<integer>();
    }
    return 0;
}

void db::manager::execute(execution_f &&db_execution) {
    auto ip = impl_ptr<impl>();

    auto execution = [db_execution = std::move(db_execution), db = ip->database](operation const &op) mutable {
        if (!op.is_canceled()) {
            db.open();
            db_execution(db, op);
            db.close();
        }
    };

    ip->queue.add_operation(operation{std::move(execution)});
}

void db::manager::insert_objects(std::string const &entity_name, std::size_t const count,
                                 insert_completion_f &&completion) {
    auto next_save_id = save_id() + 1;

    execute([completion = std::move(completion), manager = *this, entity_name, count, next_save_id](
        db::database & db, operation const &op) {
        db::begin_transaction(db);

        db::column_map db_info;
        column_maps_map inserted_objects;
        db::integer::type start_obj_id = 1;

        using insert_state = result<std::nullptr_t, insert_error>;
        insert_state state{nullptr};

        if (auto max_value = db::max(db, entity_name, object_id_field)) {
            start_obj_id = max_value.get<integer>() + 1;
        }

        db::value const save_id_value{next_save_id};

        for (auto const &idx : each_index<std::size_t>{count}) {
            db::value obj_id_value{start_obj_id + idx};

            if (!db.execute_update(db::insert_sql(entity_name, {object_id_field, save_id_field}),
                                   db::column_vector{obj_id_value, save_id_value})) {
                state = insert_state{insert_error::insert_failed};
                break;
            }

            auto const &select_result = db::select(db, entity_name, {"*"}, db::field_expr(object_id_field, "="),
                                                   {db::column_map{std::make_pair(object_id_field, obj_id_value)}});

            if (!select_result) {
                state = insert_state{insert_error::select_failed};
                break;
            }

            if (inserted_objects.count(entity_name) == 0) {
                inserted_objects.emplace(std::make_pair(entity_name, column_maps{}));
            }

            inserted_objects.at(entity_name).emplace_back(std::move(select_result.value().at(0)));
        }

        if (state) {
            if (db.execute_update(update_sql(info_table, {save_id_field}, ""), {save_id_value})) {
                auto const &select_result = db::select_db_info(db);
                if (!select_result) {
                    state = insert_state{insert_error::save_id_not_found};
                } else {
                    db_info = select_result.value();
                }
            } else {
                state = insert_state{insert_error::update_save_id_failed};
            }
        }

        if (state) {
            db::commit(db);
        } else {
            db::rollback(db);
            inserted_objects.clear();
        }

        auto lambda = [
            state = std::move(state),
            inserted_objects = std::move(inserted_objects),
            manager,
            completion = std::move(completion),
            db_info = std::move(db_info)
        ]() {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(db_info);
                auto loaded_objects = manager.impl_ptr<impl>()->load_objects(inserted_objects);
                completion(insert_result{std::move(loaded_objects)});
            } else {
                completion(insert_result{state.error()});
            }
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    });
}

db::object const &db::manager::cached_object(std::string const &entity_name, db::integer::type object_id) const {
    auto &entity_objects = impl_ptr<impl>()->entity_objects;
    if (entity_objects.count(entity_name) > 0) {
        auto &objects = entity_objects.at(entity_name);
        if (objects.count(object_id)) {
            return objects.at(object_id);
        }
    }
    return db::object::empty();
}
