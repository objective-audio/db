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

namespace yas {
namespace db {
    static auto constexpr info_table = "db_info";
    static auto constexpr version_field = "version";
}
}

struct db::manager::impl : public base::impl {
    db::database database;
    db::model model;
    operation_queue queue;
    db::entity_objects_map entity_objects;

    impl(std::string const &path, db::model const &model) : database(path), model(model), queue(), entity_objects() {
    }

    void set_object(db::object const &object) {
        auto const &entity_name = object.entity_name();
        if (entity_objects.count(entity_name) == 0) {
            entity_objects.emplace(std::make_pair(entity_name, object_map{}));
        }

        auto &objects = entity_objects.at(entity_name);

        if (auto const &object_id_value = object.object_id()) {
            auto const &object_id = object_id_value.get<integer>();
            if (objects.count(object_id)) {
                objects.erase(object_id);
            }

            objects.insert(std::make_pair(object_id, object));
        }
    }

    void set_objects(std::vector<db::object> const &objects) {
        for (auto const &object : objects) {
            set_object(object);
        }
    }
};

db::manager::manager(std::string const &db_path, db::model const &model)
    : super_class(std::make_unique<impl>(db_path, model)) {
}

db::manager::manager(std::nullptr_t) : super_class(nullptr) {
}

void db::manager::setup(setup_completion_f &&completion) {
    execute(
        [completion = std::move(completion), model = impl_ptr<impl>()->model](db::database & db, operation const &op) {
            bool result = true;

            if (db::begin_transaction(db)) {
                if (db::table_exists(db, info_table)) {
                    auto infos = db::select(db, {info_table}, {version_field}, "", {},
                                            {yas::db::field_order{version_field, yas::db::order::ascending}});
                    if (infos.size() == 0) {
                        result = false;
                    } else {
                        auto sql = update_sql(info_table, {version_field}, "");
                        if (!db.execute_update(update_sql(info_table, {version_field}, ""),
                                               {db::value{model.version().str()}})) {
                            result = false;
                        }
                    }

                    bool needs_migration = false;

                    if (result) {
                        auto const &info = *infos.rbegin();
                        if (info.count(version_field) == 0) {
                            result = false;
                        } else {
                            auto db_version_str = info.at(version_field).get<text>();
                            if (db_version_str.size() == 0) {
                                result = false;
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
                                            result = false;
                                            break;
                                        }
                                    }
                                }
                            } else {
                                // create table
                                if (!db.execute_update(entity.sql())) {
                                    result = false;
                                    break;
                                }
                            }

                            if (!result) {
                                break;
                            }

                            for (auto &rel_pair : entity.relations) {
                                auto &relation = rel_pair.second;
                                if (!db.execute_update(relation.sql())) {
                                    result = false;
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

                    if (!db.execute_update(db::create_table_sql(info_table, {version_field}))) {
                        result = false;
                    }

                    if (result) {
                        db::column_map args{std::make_pair(version_field, db::value{model.version().str()})};
                        if (!db.execute_update(db::insert_sql(info_table, {version_field}), args)) {
                            result = false;
                        }
                    }

                    // create entity tables

                    if (result) {
                        auto const &entities = model.entities();
                        for (auto &entity_pair : entities) {
                            auto &entity = entity_pair.second;
                            if (!db.execute_update(entity.sql())) {
                                result = false;
                                break;
                            }

                            for (auto &rel_pair : entity.relations) {
                                auto &relation = rel_pair.second;
                                if (!db.execute_update(relation.sql())) {
                                    result = false;
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
                result = false;
            }

            if (result) {
                db::commit(db);
            } else {
                db::rollback(db);
            }

            dispatch_async(dispatch_get_main_queue(),
                           [completion = std::move(completion), result]() { completion(result); });
        });
}

std::string const &db::manager::database_path() const {
    return impl_ptr<impl>()->database.database_path();
}

const db::database &db::manager::database() const {
    return impl_ptr<impl>()->database;
}

const db::model &db::manager::model() const {
    return impl_ptr<impl>()->model;
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
    execute([completion = std::move(completion), manager = *this, entity_name, count](db::database & db,
                                                                                      operation const &op) {
        db::begin_transaction(db);

        bool rollback = false;

        std::vector<db::object> inserted_objects;
        db::integer::type start_obj_id = 1;

        if (auto max_value = db::max(db, entity_name, object_id_field)) {
            start_obj_id = max_value.get<integer>() + 1;
        }

        for (auto const &idx : each_index<std::size_t>{count}) {
            db::value obj_id_value{start_obj_id + idx};

            if (!db.execute_update(db::insert_sql(entity_name, {object_id_field}), {obj_id_value})) {
                rollback = true;
                break;
            }

            auto maps = db::select(db, entity_name, {"*"}, db::field_expr(object_id_field, "="),
                                   {db::column_map{std::make_pair(object_id_field, obj_id_value)}});

            if (maps.size() == 0) {
                rollback = true;
                break;
            }

            db::object obj{manager.model(), entity_name};
            obj.load(maps.at(0));
            inserted_objects.emplace_back(std::move(obj));
        }

        if (rollback) {
            db::rollback(db);
            inserted_objects.clear();
        } else {
            db::commit(db);
        }

        auto lambda = [inserted_objects = std::move(inserted_objects), manager, completion = std::move(completion)]() {
            manager.impl_ptr<impl>()->set_objects(inserted_objects);
            completion(inserted_objects);
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    });
}

db::object const &db::manager::cached_object(std::string const &entity_name, db::integer::type object_id) {
    auto &entity_objects = impl_ptr<impl>()->entity_objects;
    if (entity_objects.count(entity_name) > 0) {
        auto &objects = entity_objects.at(entity_name);
        if (objects.count(object_id)) {
            return objects.at(object_id);
        }
    }
    return db::object::empty();
}
