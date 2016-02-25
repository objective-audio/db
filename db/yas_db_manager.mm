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
    return _type != error_type::none;
}

db::manager::error_type const &db::manager::error::type() const {
    return _type;
}

db::error const &db::manager::error::database_error() const {
    return _db_error;
}

#pragma mark - utils

namespace yas {
namespace db {
    using object_data_result = result<db::object_data, db::error>;
    using object_datas_result = result<db::object_data_vector, db::error>;

    object_data_result fetch_object_data(database &db, relation_map const &rel_models, db::value_map &attrs) {
        db::value_vector_map relations;

        if (attrs.count(save_id_field)) {
            for (auto const &rel_model_pair : rel_models) {
                auto const &rel_name = rel_model_pair.first;
                auto const &table_name = rel_model_pair.second.table_name;
                std::string where_exprs =
                    joined({equal_field_expr(save_id_field), equal_field_expr(src_obj_id_field)}, " and ");
                db::select_option option{.table = table_name,
                                         .where_exprs = std::move(where_exprs),
                                         .arguments = {{save_id_field, attrs.at(save_id_field)},
                                                       {src_obj_id_field, attrs.at(object_id_field)}}};

                if (auto select_result = db::select(db, option)) {
                    auto const &result_rels = select_result.value();
                    db::value_vector rel_tgts;
                    rel_tgts.reserve(result_rels.size());
                    for (auto const &result_rel : result_rels) {
                        rel_tgts.push_back(result_rel.at(tgt_obj_id_field));
                    }
                    relations.emplace(std::make_pair(rel_name, std::move(rel_tgts)));
                } else {
                    return object_data_result{std::move(select_result.error())};
                }
            }
        }

        return object_data_result{object_data{.attributes = std::move(attrs), .relations = std::move(relations)}};
    }

    object_datas_result fetch_entity_object_datas(database &db, std::string const &entity_name,
                                                  relation_map const &rel_models,
                                                  value_map_vector const &entity_attrs) {
        db::object_data_vector entity_datas;
        entity_datas.reserve(entity_attrs.size());

        for (value_map attrs : entity_attrs) {
            if (auto obj_data_result = fetch_object_data(db, rel_models, attrs)) {
                entity_datas.emplace_back(std::move(obj_data_result.value()));
            } else {
                return object_datas_result{std::move(obj_data_result.error())};
            }
        }

        return object_datas_result{std::move(entity_datas)};
    }

    result<db::value, db::manager::error> select_current_save_id(database &db) {
        db::manager::result_t state{nullptr};

        db::value current_save_id{nullptr};
        if (auto db_info_result = db::select_db_info(db)) {
            auto &db_info = db_info_result.value();
            if (db_info.count(current_save_id_field)) {
                current_save_id = db_info.at(current_save_id_field);
            } else {
                state = manager::result_t{manager::error{manager::error_type::save_id_not_found}};
            }
        } else {
            state = manager::result_t{
                manager::error{manager::error_type::select_info_failed, std::move(db_info_result.error())}};
        }

        if (state) {
            return result<db::value, db::manager::error>{std::move(current_save_id)};
        } else {
            return result<db::value, db::manager::error>{state.error()};
        }
    }

    db::manager::result_t delete_current_to_last(db::manager &manager, db::value const &current_save_id,
                                                 db::value const &last_save_id) {
        auto const delete_exprs = joined({expr(db::save_id_field, ">", to_string(current_save_id)),
                                          expr(save_id_field, "<=", to_string(last_save_id))},
                                         " and ");
        auto &db = manager.database();
        auto const &entity_models = manager.model().entities();
        for (auto const &entity_pair : entity_models) {
            auto const &entity_name = entity_pair.first;

            if (auto delete_result = db.execute_update(db::delete_sql(entity_name, delete_exprs))) {
                for (auto const &rel_pair : entity_pair.second.relations) {
                    auto const table_name = rel_pair.second.table_name;

                    if (auto ul = unless(db.execute_update(db::delete_sql(table_name, delete_exprs)))) {
                        return db::manager::result_t{
                            db::manager::error{db::manager::error_type::delete_failed, std::move(ul.value.error())}};
                    }
                }
            } else {
                return db::manager::result_t{
                    db::manager::error{db::manager::error_type::delete_failed, std::move(delete_result.error())}};
            }
        }

        return db::manager::result_t{nullptr};
    }

    const_object_vector_map to_const_vector_objects(db::model const &model, object_data_vector_map const &datas) {
        const_object_vector_map objects;
        for (auto const &entity_pair : datas) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_datas = entity_pair.second;

            const_object_vector entity_objects;
            entity_objects.reserve(entity_datas.size());

            for (auto const &data : entity_datas) {
                if (const_object obj{model, entity_name, data}) {
                    entity_objects.emplace_back(std::move(obj));
                }
            }

            objects.emplace(std::make_pair(entity_name, std::move(entity_objects)));
        }
        return objects;
    }

    const_object_map_map to_const_map_objects(db::model const &model, object_data_vector_map const &datas) {
        const_object_map_map objects;
        for (auto const &entity_pair : datas) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_datas = entity_pair.second;

            const_object_map entity_objects;
            entity_objects.reserve(entity_datas.size());

            for (auto const &data : entity_datas) {
                if (const_object obj{model, entity_name, data}) {
                    entity_objects.emplace(std::make_pair(obj.object_id().get<integer>(), std::move(obj)));
                }
            }

            objects.emplace(std::make_pair(entity_name, std::move(entity_objects)));
        }
        return objects;
    }
}
}

#pragma mark - impl

struct db::manager::impl : public base::impl {
    db::database database;
    db::model model;
    operation_queue queue;
    db::weak_object_map_map cached_objects;
    db::object_map_map changed_objects;
    db::value_map db_info;

    impl(std::string const &path, db::model const &model, priority_t const priority_count)
        : database(path), model(model), queue(priority_count), cached_objects() {
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

        return db::object::null_object();
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

    object_map_map load_map_object_datas(object_data_vector_map const &datas) {
        object_map_map loaded_objects;
        for (auto const &entity_pair : datas) {
            auto const &entity_name = entity_pair.first;
            auto const &entity_datas = entity_pair.second;

            object_map objects;
            objects.reserve(entity_datas.size());

            for (auto const &data : entity_datas) {
                if (auto const obj = load_object_data(entity_name, data)) {
                    objects.emplace(std::make_pair(obj.object_id().get<integer>(), std::move(obj)));
                }
            }

            loaded_objects.emplace(std::make_pair(entity_name, std::move(objects)));
        }
        return loaded_objects;
    }

    void clear_objects() {
        for (auto &entity_pair : cached_objects) {
            for (auto &object_pair : entity_pair.second) {
                if (auto object = object_pair.second.lock()) {
                    object.clear_data();
                }
            }
        }
        cached_objects.clear();
    }

    void set_db_info(db::value_map &&info) {
        db_info = std::move(info);
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
        return db::object::null_object();
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
            erase_if_exists(cached_objects.at(entity_name), object_id);
        }
    }

    void execute(execution_f &&execution, priority_t const priority) {
        auto op_lambda = [execution = std::move(execution), manager = cast<manager>()](operation const &op) mutable {
            if (!op.is_canceled()) {
                auto &db = manager.impl_ptr<impl>()->database;
                db.open();
                execution(manager, op);
                db.close();
            }
        };

        queue.add_operation(operation{std::move(op_lambda)}, priority);
    }

    void execute_setup(std::function<void(manager &, result_t &&, value_map &&)> &&completion) {
        execute(
            [completion = std::move(completion)](db::manager & manager, operation const &op) {
                auto &db = manager.database();
                auto const &model = manager.model();

                db::value_map db_info;
                result_t state{nullptr};

                if (auto begin_result = db::begin_transaction(db)) {
                    if (db::table_exists(db, info_table)) {
                        bool needs_migration = false;

                        if (auto select_result = db::select(
                                db, {.table = info_table, .fields = {version_field}, .limit_range = db::range{0, 1}})) {
                            auto const update_info_result = db.execute_update(update_sql(info_table, {version_field}),
                                                                              {db::value{model.version().str()}});
                            if (update_info_result) {
                                auto const &infos = select_result.value();
                                auto const &info = *infos.rbegin();
                                if (info.count(version_field) == 0) {
                                    state = result_t{error{error_type::version_not_found}};
                                } else {
                                    auto db_version_str = info.at(version_field).get<text>();
                                    if (db_version_str.size() == 0) {
                                        state = result_t{error{error_type::invalid_version_text}};
                                    } else {
                                        auto const db_version = yas::version{db_version_str};
                                        if (db_version < model.version()) {
                                            needs_migration = true;
                                        }
                                    }
                                }
                            } else {
                                state = result_t{
                                    error{error_type::update_info_failed, std::move(update_info_result.error())}};
                            }
                        } else {
                            state = result_t{error{error_type::select_info_failed, std::move(select_result.error())}};
                        }

                        if (state && needs_migration) {
                            for (auto const &entity_pair : model.entities()) {
                                auto const &entity_name = entity_pair.first;
                                auto const &entity = entity_pair.second;

                                if (db::table_exists(db, entity_name)) {
                                    // alter table
                                    for (auto const &attr_pair : entity.attributes) {
                                        if (!db::column_exists(db, attr_pair.first, entity_name)) {
                                            auto const &attr = attr_pair.second;
                                            if (auto ul = unless(
                                                    db.execute_update(alter_table_sql(entity_name, attr.sql())))) {
                                                state = result_t{error{error_type::alter_entity_table_failed,
                                                                       std::move(ul.value.error())}};
                                                break;
                                            }
                                        }
                                    }
                                } else {
                                    // create table
                                    if (auto ul = unless(db.execute_update(entity.sql_for_create()))) {
                                        state = result_t{
                                            error{error_type::create_entity_table_failed, std::move(ul.value.error())}};
                                        break;
                                    }
                                }

                                if (state) {
                                    for (auto &rel_pair : entity.relations) {
                                        if (auto ul = unless(db.execute_update(rel_pair.second.sql_for_create()))) {
                                            state = result_t{error{error_type::create_relation_table_failed,
                                                                   std::move(ul.value.error())}};
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
                                            state = result_t{
                                                error{error_type::create_index_failed, std::move(ul.value.error())}};
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // create information table

                        if (auto create_result = db.execute_update(db::create_table_sql(
                                info_table, {version_field, current_save_id_field, last_save_id_field}))) {
                            db::value_vector args{db::value{model.version().str()}, db::value{integer::type{0}},
                                                  db::value{integer::type{0}}};
                            if (auto ul = unless(db.execute_update(
                                    db::insert_sql(info_table,
                                                   {version_field, current_save_id_field, last_save_id_field}),
                                    args))) {
                                state = result_t{error{error_type::insert_info_failed, std::move(ul.value.error())}};
                            }
                        } else {
                            state =
                                result_t{error{error_type::create_info_table_failed, std::move(create_result.error())}};
                        }

                        // create entity tables

                        if (state) {
                            auto const &entities = model.entities();
                            for (auto &entity_pair : entities) {
                                auto &entity = entity_pair.second;
                                if (auto ul = unless(db.execute_update(entity.sql_for_create()))) {
                                    state = result_t{
                                        error{error_type::create_entity_table_failed, std::move(ul.value.error())}};
                                    break;
                                }

                                for (auto &rel_pair : entity.relations) {
                                    if (auto ul = unless(db.execute_update(rel_pair.second.sql_for_create()))) {
                                        state = result_t{error{error_type::create_relation_table_failed,
                                                               std::move(ul.value.error())}};
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
                                        result_t{error{error_type::create_index_failed, std::move(ul.value.error())}};
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
                    state = result_t{error{error_type::begin_transaction_failed, std::move(begin_result.error())}};
                }

                if (state) {
                    if (auto select_result = select_db_info(db)) {
                        db_info = std::move(select_result.value());
                    } else {
                        state = result_t{error{error_type::select_info_failed, std::move(select_result.error())}};
                    }
                }

                completion(manager, std::move(state), std::move(db_info));
            },
            0);
    }

    void execute_clear(std::function<void(manager &, result_t &&, value_map &&)> &&completion,
                       priority_t const priority) {
        execute(
            [completion = std::move(completion)](db::manager & manager, operation const &op) {
                auto &db = manager.database();
                auto const &model = manager.model();

                db::value_map db_info;
                result_t state{nullptr};

                if (auto begin_result = db::begin_transaction(db)) {
                    for (auto const &entity_pair : model.entities()) {
                        auto const &entity = entity_pair.second;
                        auto const &table_name = entity.name;

                        if (auto delete_result = db.execute_update(db::delete_sql(table_name))) {
                            for (auto const &rel_pair : entity.relations) {
                                auto const table_name = rel_pair.second.table_name;

                                if (auto ul = unless(db.execute_update(db::delete_sql(table_name)))) {
                                    state = result_t{error{error_type::delete_failed, std::move(ul.value.error())}};
                                    break;
                                }
                            }
                        } else {
                            state = result_t{error{error_type::delete_failed, std::move(delete_result.error())}};
                            break;
                        }
                    }
                } else {
                    state = result_t{error{error_type::begin_transaction_failed, std::move(begin_result.error())}};
                }

                if (state) {
                    auto const sql = update_sql(info_table, {current_save_id_field, last_save_id_field});
                    db::value_vector const params{db::value{integer::type{0}}, db::value{integer::type{0}}};
                    if (auto update_result = db.execute_update(sql, params)) {
                        if (auto select_result = db::select_db_info(db)) {
                            db_info = std::move(select_result.value());
                        } else {
                            state = result_t{error{error_type::select_info_failed, std::move(select_result.error())}};
                        }
                    } else {
                        state = result_t{error{error_type::update_info_failed, std::move(update_result.error())}};
                    }
                }

                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                    db_info.clear();
                }

                completion(manager, std::move(state), std::move(db_info));
            },
            priority);
    }

    void execute_insert(
        insert_preparation_values_f &&preparation,
        std::function<void(db::manager &, result_t &&, object_data_vector_map &&, db::value_map &&)> &&completion,
        priority_t const priority) {
        execute([preparation = std::move(preparation), completion = std::move(completion)](db::manager & manager,
                                                                                           operation const &op) {
            value_map_vector_map values;

            auto preparation_on_main = [&values, &manager, &preparation]() { values = preparation(manager); };

            dispatch_sync(dispatch_get_main_queue(), std::move(preparation_on_main));

            auto &db = manager.database();

            db::value_map db_info;
            object_data_vector_map inserted_datas;
            db::integer::type start_obj_id = 1;

            result_t state{nullptr};

            if (auto begin_result = db::begin_transaction(db)) {
                db::value current_save_id{nullptr};
                db::value last_save_id{nullptr};
                db::value next_save_id{nullptr};

                if (auto select_result = db::select_db_info(db)) {
                    auto const &db_info = select_result.value();
                    if (db_info.count(current_save_id_field)) {
                        current_save_id = db_info.at(current_save_id_field);
                        next_save_id = db::value{current_save_id.get<integer>() + 1};
                    } else {
                        state = result_t{error{error_type::save_id_not_found}};
                    }

                    if (db_info.count(last_save_id_field)) {
                        last_save_id = db_info.at(last_save_id_field);
                    } else {
                        state = result_t{error{error_type::save_id_not_found}};
                    }
                } else {
                    state = result_t{error{error_type::select_info_failed, std::move(select_result.error())}};
                }

                if (state && current_save_id && last_save_id) {
                    if (current_save_id.get<integer>() < last_save_id.get<integer>()) {
                        state = delete_current_to_last(manager, current_save_id, last_save_id);
                    }
                }

                if (state) {
                    for (auto &values_pair : values) {
                        auto const &entity_name = values_pair.first;
                        auto &entity_values = values_pair.second;

                        if (auto max_value = db::max(db, entity_name, object_id_field)) {
                            start_obj_id = max_value.get<integer>() + 1;
                        }

                        std::size_t idx = 0;
                        for (auto &obj_values : entity_values) {
                            db::value obj_id_value{start_obj_id + idx};

                            std::vector<std::string> fields{object_id_field, save_id_field};
                            db::value_vector args{obj_id_value, next_save_id};

                            fields.reserve(obj_values.size() + 2);
                            args.reserve(obj_values.size() + 2);

                            for (auto &value : obj_values) {
                                fields.push_back(value.first);
                                args.emplace_back(std::move(value.second));
                            }

                            auto sql = db::insert_sql(entity_name, fields);
                            if (auto ul = unless(db.execute_update(std::move(sql), std::move(args)))) {
                                state =
                                    result_t{error{error_type::insert_attributes_failed, std::move(ul.value.error())}};
                                break;
                            }

                            db::select_option option{.table = entity_name,
                                                     .where_exprs = db::equal_field_expr(object_id_field),
                                                     .arguments = {{std::make_pair(object_id_field, obj_id_value)}}};

                            auto select_result = db::select(db, std::move(option));
                            if (select_result) {
                                if (inserted_datas.count(entity_name) == 0) {
                                    object_data_vector entity_datas{};
                                    entity_datas.reserve(entity_values.size());
                                    inserted_datas.emplace(std::make_pair(entity_name, std::move(entity_datas)));
                                }

                                inserted_datas.at(entity_name)
                                    .emplace_back(object_data{.attributes = std::move(select_result.value().at(0))});
                            } else {
                                state = result_t{error{error_type::select_failed, std::move(select_result.error())}};
                                break;
                            }

                            ++idx;
                        }
                    }
                }

                if (state) {
                    auto const sql = update_sql(info_table, {current_save_id_field, last_save_id_field}, "");
                    db::value_vector const params{next_save_id, next_save_id};
                    if (auto update_result = db.execute_update(sql, params)) {
                        if (auto select_result = db::select_db_info(db)) {
                            db_info = select_result.value();
                        } else {
                            state = result_t{error{error_type::select_info_failed, std::move(select_result.error())}};
                        }
                    } else {
                        state = result_t{error{error_type::update_info_failed, std::move(update_result.error())}};
                    }
                }

                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                    inserted_datas.clear();
                }
            } else {
                state = result_t{error{error_type::begin_transaction_failed, std::move(begin_result.error())}};
            }

            completion(manager, std::move(state), std::move(inserted_datas), std::move(db_info));
        },
                priority);
    }

    void execute_fetch_object_datas(fetch_preparation_option_f &&preparation,
                                    std::function<void(db::manager &manager, result_t &&state,
                                                       object_data_vector_map &&fetched_datas)> &&completion,
                                    priority_t const priority) {
        execute([preparation = std::move(preparation), completion = std::move(completion)](db::manager & manager,
                                                                                           operation const &) {
            db::select_option option;

            auto preparation_on_main = [&option, &manager, &preparation]() { option = preparation(manager); };

            dispatch_sync(dispatch_get_main_queue(), std::move(preparation_on_main));

            std::string const entity_name = option.table;

            auto &db = manager.database();

            auto const &rel_models = manager.model().relations(entity_name);
            result_t state{nullptr};

            object_data_vector_map fetched_datas;

            if (auto begin_result = db::begin_transaction(db)) {
                db::value current_save_id{nullptr};
                auto cur_save_id_result = select_current_save_id(db);
                if (cur_save_id_result) {
                    current_save_id = std::move(cur_save_id_result.value());

                    if (auto select_result = db::select_last(db, std::move(option), current_save_id)) {
                        auto &entity_attrs = select_result.value();
                        if (auto obj_datas_result =
                                fetch_entity_object_datas(db, entity_name, rel_models, entity_attrs)) {
                            auto &entity_obj_datas = obj_datas_result.value();
                            if (entity_obj_datas.size() > 0) {
                                fetched_datas.emplace(std::make_pair(entity_name, std::move(entity_obj_datas)));
                            }
                        } else {
                            state = result_t{
                                error{error_type::fetch_object_datas_failed, std::move(obj_datas_result.error())}};
                        }
                    } else {
                        state = result_t{error{error_type::select_last_failed, std::move(select_result.error())}};
                    }
                } else {
                    state = result_t{std::move(cur_save_id_result.error())};
                }

                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                    fetched_datas.clear();
                }
            } else {
                state = result_t{error{error_type::begin_transaction_failed, std::move(begin_result.error())}};
            }

            completion(manager, std::move(state), std::move(fetched_datas));
        },
                priority);
    }

    void execute_fetch_object_datas(fetch_preparation_ids_f &&preparation,
                                    std::function<void(db::manager &manager, result_t &&state,
                                                       object_data_vector_map &&fetched_datas)> &&completion,
                                    priority_t const priority) {
        execute([completion = std::move(completion), preparation = std::move(preparation)](manager & manager,
                                                                                           operation const &) {
            db::integer_set_map obj_ids;

            auto preparation_on_main = [&obj_ids, &manager, &preparation]() { obj_ids = preparation(manager); };

            dispatch_sync(dispatch_get_main_queue(), std::move(preparation_on_main));

            auto &db = manager.database();

            result_t state{nullptr};

            object_data_vector_map fetched_datas;

            if (auto begin_result = db::begin_transaction(db)) {
                db::value current_save_id{nullptr};
                auto cur_save_id_result = select_current_save_id(db);
                if (cur_save_id_result) {
                    current_save_id = std::move(cur_save_id_result.value());

                    for (auto const &entity_pair : obj_ids) {
                        auto const &entity_name = entity_pair.first;
                        auto const &rel_models = manager.model().relations(entity_name);

                        auto const &entity_obj_ids = entity_pair.second;
                        db::select_option option{
                            .table = entity_name,
                            .where_exprs =
                                object_id_field + " in (" +
                                joined(entity_obj_ids, ",", [](auto const &rel_id) { return std::to_string(rel_id); }) +
                                ")"};

                        if (auto select_result = db::select_last(db, std::move(option), current_save_id)) {
                            auto &entity_attrs = select_result.value();
                            if (auto obj_datas_result =
                                    fetch_entity_object_datas(db, entity_name, rel_models, entity_attrs)) {
                                fetched_datas.emplace(std::make_pair(entity_name, std::move(obj_datas_result.value())));
                            } else {
                                state = result_t{
                                    error{error_type::fetch_object_datas_failed, std::move(obj_datas_result.error())}};
                                break;
                            }
                        } else {
                            state = result_t{error{error_type::select_last_failed, std::move(select_result.error())}};
                            break;
                        }
                    }
                } else {
                    state = result_t{std::move(cur_save_id_result.error())};
                }
            } else {
                state = result_t{error{error_type::begin_transaction_failed, std::move(begin_result.error())}};
            }

            completion(manager, std::move(state), std::move(fetched_datas));
        },
                priority);
    }

    void execute_save(
        std::function<void(db::manager &manager, result_t &&state, db::object_data_vector_map &&saved_datas,
                           db::value_map &&db_info)> &&completion,
        priority_t const priority) {
        execute(
            [completion = std::move(completion)](manager & manager, operation const &) {
                db::object_data_vector_map changed_datas;
                auto manager_impl = manager.impl_ptr<impl>();

                auto get_change_lambda = [&manager_impl, &changed_datas]() {
                    changed_datas = manager_impl->changed_datas_for_save();
                };

                dispatch_sync(dispatch_get_main_queue(), get_change_lambda);

                auto &db = manager.database();

                db::value_map db_info;
                db::object_data_vector_map saved_datas;

                result_t state{nullptr};

                if (changed_datas.size() > 0) {
                    if (auto begin_result = db::begin_transaction(db)) {
                        db::value current_save_id{nullptr};
                        db::value next_save_id{nullptr};
                        db::value last_save_id{nullptr};

                        if (auto select_result = db::select_db_info(db)) {
                            auto const &db_info = select_result.value();
                            if (db_info.count(current_save_id_field)) {
                                current_save_id = db_info.at(current_save_id_field);
                                next_save_id = db::value{current_save_id.get<integer>() + 1};
                            } else {
                                state = result_t{error{error_type::save_id_not_found}};
                            }

                            if (db_info.count(last_save_id_field)) {
                                last_save_id = db_info.at(last_save_id_field);
                            } else {
                                state = result_t{error{error_type::save_id_not_found}};
                            }
                        } else {
                            state = result_t{error{error_type::select_info_failed, std::move(select_result.error())}};
                        }

                        if (state && next_save_id && current_save_id && last_save_id &&
                            next_save_id.get<integer>() > 0) {
                            if (current_save_id.get<integer>() < last_save_id.get<integer>()) {
                                state = delete_current_to_last(manager, current_save_id, last_save_id);
                            }
                        } else {
                            state = result_t{error{error_type::save_id_not_found}};
                        }

                        if (state) {
                            auto const &save_id_pair = std::make_pair(save_id_field, next_save_id);

                            for (auto const &entity_pair : changed_datas) {
                                auto const &entity_name = entity_pair.first;
                                auto const &changed_entity_datas = entity_pair.second;
                                auto const entity_insert_sql = manager.model().entity(entity_name).sql_for_insert();
                                auto const &rel_models = manager.model().relations(entity_name);

                                db::object_data_vector entity_saved_datas;

                                for (auto data : changed_entity_datas) {
                                    erase_if_exists(data.attributes, id_field);
                                    replace(data.attributes, save_id_field, next_save_id);

                                    if (auto insert_result = db.execute_update(entity_insert_sql, data.attributes)) {
                                        if (auto row_result = db.last_insert_row_id()) {
                                            auto const src_rowid_pair =
                                                std::make_pair(src_id_field, db::value{row_result.value()});
                                            auto const src_obj_id_pair =
                                                std::make_pair(src_obj_id_field, data.attributes.at(object_id_field));

                                            for (auto const &rel_pair : data.relations) {
                                                auto const &rel_name = rel_pair.first;
                                                auto const &rel = rel_pair.second;
                                                auto const &rel_model = rel_models.at(rel_name);
                                                auto const &rel_insert_sql = rel_model.sql_for_insert();

                                                for (auto const &rel_tgt_obj_id : rel) {
                                                    auto tgt_obj_id_pair =
                                                        std::make_pair(tgt_obj_id_field, rel_tgt_obj_id);
                                                    db::value_map args{src_rowid_pair, src_obj_id_pair,
                                                                       std::move(tgt_obj_id_pair), save_id_pair};
                                                    if (auto ul = unless(
                                                            db.execute_update(rel_insert_sql, std::move(args)))) {
                                                        state = result_t{error{error_type::insert_relation_failed,
                                                                               std::move(ul.value.error())}};
                                                        break;
                                                    }
                                                }
                                            }
                                        } else {
                                            state = result_t{error{error_type::last_insert_rowid_failed,
                                                                   std::move(row_result.error())}};
                                        }
                                    } else {
                                        state = result_t{error{error_type::insert_attributes_failed,
                                                               std::move(insert_result.error())}};
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
                            auto const sql = update_sql(info_table, {current_save_id_field, last_save_id_field});
                            db::value_vector const params{next_save_id, next_save_id};
                            if (auto ul = unless(db.execute_update(sql, params))) {
                                state = result_t{error{error_type::update_info_failed, std::move(ul.value.error())}};
                            }
                        }

                        if (state) {
                            db::commit(db);
                        } else {
                            db::rollback(db);
                            saved_datas.clear();
                        }
                    } else {
                        state = result_t{error{error_type::begin_transaction_failed, std::move(begin_result.error())}};
                    }
                }

                if (state) {
                    if (auto const select_result = db::select_db_info(db)) {
                        db_info = std::move(select_result.value());
                    } else {
                        state = result_t{error{error_type::select_info_failed, std::move(select_result.error())}};
                    }
                }

                completion(manager, std::move(state), std::move(saved_datas), std::move(db_info));
            },
            priority);
    }

    void execute_revert(
        revert_preparation_f preparation,
        std::function<void(db::manager &manager, result_t &&state, object_data_vector_map &&reverted_datas,
                           db::value_map &&db_info)> &&completion,
        priority_t const priority) {
        execute([preparation = std::move(preparation), completion = std::move(completion)](manager & manager,
                                                                                           operation const &) {
            db::integer::type rev_save_id;

            auto preparation_on_main = [&manager, &rev_save_id, &preparation]() { rev_save_id = preparation(manager); };

            dispatch_sync(dispatch_get_main_queue(), std::move(preparation_on_main));

            auto &db = manager.database();

            result_t state{nullptr};

            value_map_vector_map reverted_attrs;
            object_data_vector_map reverted_datas;
            db::value_map db_info;

            if (auto begin_result = db::begin_transaction(db)) {
                db::integer::type last_save_id = 0;
                db::integer::type current_save_id = 0;

                if (auto select_result = db::select_db_info(db)) {
                    auto const &db_info = select_result.value();
                    if (db_info.count(current_save_id_field)) {
                        current_save_id = db_info.at(current_save_id_field).get<integer>();
                    }
                    if (db_info.count(last_save_id_field)) {
                        last_save_id = db_info.at(last_save_id_field).get<integer>();
                    }
                } else {
                    state = result_t{error{error_type::select_info_failed, std::move(select_result.error())}};
                }

                auto const &entity_models = manager.model().entities();

                if (rev_save_id == current_save_id || last_save_id < rev_save_id) {
                    state = result_t{error{error_type::out_of_range_save_id}};
                } else {
                    for (auto const &entity_model_pair : entity_models) {
                        auto const &entity_name = entity_model_pair.first;
                        if (auto select_result = db::select_revert(db, entity_name, rev_save_id, current_save_id)) {
                            reverted_attrs.emplace(std::make_pair(entity_name, std::move(select_result.value())));
                        } else {
                            reverted_attrs.clear();
                            state = result_t{error{error_type::select_revert_failed, std::move(select_result.error())}};
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
                                fetch_entity_object_datas(db, entity_name, rel_models, entity_attrs)) {
                            reverted_datas.emplace(std::make_pair(entity_name, std::move(obj_datas_result.value())));
                        } else {
                            reverted_attrs.clear();
                            reverted_datas.clear();
                            state = result_t{
                                error{error_type::fetch_object_datas_failed, std::move(obj_datas_result.error())}};
                            break;
                        }
                    }
                }

                if (state) {
                    db::value const save_id{rev_save_id};
                    auto const sql = update_sql(info_table, {current_save_id_field});
                    if (auto update_result = db.execute_update(sql, {save_id})) {
                        if (auto select_result = db::select_db_info(db)) {
                            db_info = std::move(select_result.value());
                        } else {
                            state = result_t{error{error_type::select_info_failed, std::move(select_result.error())}};
                        }
                    } else {
                        state = result_t{error{error_type::update_save_id_failed, std::move(update_result.error())}};
                    }
                }

                if (state) {
                    db::commit(db);
                } else {
                    db::rollback(db);
                    reverted_datas.clear();
                }
            } else {
                state = result_t{error{error_type::begin_transaction_failed, std::move(begin_result.error())}};
            }

            completion(manager, std::move(state), std::move(reverted_datas), std::move(db_info));
        },
                priority);
    }
};

#pragma mark - manager

db::manager::manager(std::string const &db_path, db::model const &model, size_t const priority_count)
    : super_class(std::make_unique<impl>(db_path, model, priority_count)) {
}

db::manager::manager(std::nullptr_t) : super_class(nullptr) {
}

void db::manager::suspend() {
    impl_ptr<impl>()->queue.suspend();
}

void db::manager::resume() {
    impl_ptr<impl>()->queue.resume();
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

void db::manager::setup(completion_f completion) {
    auto impl_completion = [completion = std::move(completion)](manager & manager, result_t && state,
                                                                value_map && db_info) mutable {
        auto lambda = [
            manager,
            state = std::move(state),
            db_info = std::move(db_info),
            completion = std::move(completion)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
            }
            completion(manager, std::move(state));
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_setup(std::move(impl_completion));
}

void db::manager::clear(completion_f completion, priority_t const priority) {
    auto impl_completion = [completion = std::move(completion)](manager & manager, result_t && state,
                                                                value_map && db_info) {
        auto lambda = [
            completion = std::move(completion),
            manager,
            state = std::move(state),
            db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                manager.impl_ptr<impl>()->clear_objects();
            }
            completion(manager, std::move(state));
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_clear(std::move(impl_completion), priority);
}

void db::manager::execute(execution_f &&execution, priority_t const priority) {
    impl_ptr<impl>()->execute(std::move(execution), priority);
}

void db::manager::insert_objects(insert_preparation_count_f preparation, vector_completion_f completion,
                                 priority_t const priority) {
    auto impl_preparation = [preparation = std::move(preparation)](auto &manager) {
        auto counts = preparation(manager);
        db::value_map_vector_map values{};

        for (auto &count_pair : counts) {
            values.emplace(std::make_pair(count_pair.first, db::value_map_vector{count_pair.second}));
        }

        return values;
    };

    insert_objects(std::move(impl_preparation), std::move(completion), priority);
}

void db::manager::insert_objects(insert_preparation_values_f preparation, vector_completion_f completion,
                                 priority_t const priority) {
    auto impl_completion = [completion = std::move(completion)](
        db::manager & manager, result_t && state, object_data_vector_map && inserted_datas, db::value_map && db_info) {
        auto lambda = [
            state = std::move(state),
            inserted_datas = std::move(inserted_datas),
            manager,
            completion = std::move(completion),
            db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects = manager.impl_ptr<impl>()->load_object_datas(inserted_datas);
                completion(manager, vector_result_t{std::move(loaded_objects)});
            } else {
                completion(manager, vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_insert(std::move(preparation), std::move(impl_completion), priority);
}

void db::manager::fetch_objects(fetch_preparation_option_f preparation, vector_completion_f completion,
                                priority_t const priority) {
    auto impl_completion = [completion = std::move(completion)](db::manager & manager, result_t && state,
                                                                object_data_vector_map && fetched_datas) {
        auto lambda = [
            state = std::move(state),
            completion = std::move(completion),
            fetched_datas = std::move(fetched_datas),
            manager
        ]() mutable {
            if (state) {
                auto loaded_objects = manager.impl_ptr<impl>()->load_object_datas(fetched_datas);
                completion(manager, vector_result_t{std::move(loaded_objects)});
            } else {
                completion(manager, vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), priority);
}

void db::manager::fetch_const_objects(fetch_preparation_option_f preparation, const_vector_completion_f completion,
                                      priority_t const priority) {
    auto impl_completion = [completion = std::move(completion)](db::manager & manager, result_t && state,
                                                                object_data_vector_map && fetched_datas) {
        auto lambda = [
            state = std::move(state),
            completion = std::move(completion),
            fetched_datas = std::move(fetched_datas),
            manager
        ]() mutable {
            if (state) {
                completion(manager, const_vector_result_t{to_const_vector_objects(manager.model(), fetched_datas)});
            } else {
                completion(manager, const_vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), priority);
}

void db::manager::fetch_objects(fetch_preparation_ids_f preparation, map_completion_f completion,
                                priority_t const priority) {
    auto impl_completion = [completion = std::move(completion)](db::manager & manager, result_t && state,
                                                                object_data_vector_map && fetched_datas) {
        auto lambda = [
            manager,
            completion = std::move(completion),
            state = std::move(state),
            fetched_datas = std::move(fetched_datas)
        ]() mutable {
            if (state) {
                auto loaded_objects = manager.impl_ptr<impl>()->load_map_object_datas(fetched_datas);
                completion(manager, map_result_t{std::move(loaded_objects)});
            } else {
                completion(manager, map_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), priority);
}

void db::manager::fetch_const_objects(fetch_preparation_ids_f preparation, const_map_completion_f completion,
                                      priority_t const priority) {
    auto impl_completion = [completion = std::move(completion)](db::manager & manager, result_t && state,
                                                                object_data_vector_map && fetched_datas) {
        auto lambda = [
            manager,
            completion = std::move(completion),
            state = std::move(state),
            fetched_datas = std::move(fetched_datas)
        ]() mutable {
            if (state) {
                completion(manager, const_map_result_t{to_const_map_objects(manager.model(), fetched_datas)});
            } else {
                completion(manager, const_map_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_fetch_object_datas(std::move(preparation), std::move(impl_completion), priority);
}

void db::manager::save(vector_completion_f completion, priority_t const priority) {
    auto impl_completion = [completion = std::move(completion)](
        db::manager & manager, result_t && state, db::object_data_vector_map && saved_datas, db::value_map && db_info) {
        auto lambda = [
            manager,
            state = std::move(state),
            completion = std::move(completion),
            saved_datas = std::move(saved_datas),
            db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects = manager.impl_ptr<impl>()->load_object_datas(saved_datas);
                manager.impl_ptr<impl>()->changed_objects.clear();
                completion(manager, vector_result_t{std::move(loaded_objects)});
            } else {
                completion(manager, vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_save(std::move(impl_completion), priority);
}

void db::manager::revert(revert_preparation_f preparation, vector_completion_f completion, priority_t const priority) {
    auto impl_completion = [completion = std::move(completion)](
        db::manager & manager, result_t && state, object_data_vector_map && reverted_datas, db::value_map && db_info) {
        auto lambda = [
            manager,
            state = std::move(state),
            completion = std::move(completion),
            reverted_datas = std::move(reverted_datas),
            db_info = std::move(db_info)
        ]() mutable {
            if (state) {
                manager.impl_ptr<impl>()->set_db_info(std::move(db_info));
                auto loaded_objects = manager.impl_ptr<impl>()->load_object_datas(reverted_datas);
                manager.impl_ptr<impl>()->changed_objects.clear();
                completion(manager, vector_result_t{std::move(loaded_objects)});
            } else {
                completion(manager, vector_result_t{std::move(state.error())});
            }
        };

        dispatch_sync(dispatch_get_main_queue(), std::move(lambda));
    };

    impl_ptr<impl>()->execute_revert(std::move(preparation), std::move(impl_completion), priority);
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

std::string yas::to_string(db::manager::error_type const &error) {
    switch (error) {
        case db::manager::error_type::begin_transaction_failed:
            return "begin_transaction_failed";
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
