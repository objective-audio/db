//
//  yas_sample_db_controller.mm
//

#import <Foundation/Foundation.h>
#include "yas_cf_utils.h"
#include "yas_cf_ref.h"
#include "yas_objc_ptr.h"
#include "yas_sample_db_controller.h"

using namespace yas;
using namespace yas::sample;

namespace yas {
namespace sample {
    std::string const entity_name_a = "entity_a";
    std::string const entity_name_b = "entity_b";
}
}

#pragma mark - change_info

db_controller::change_info::change_info(std::nullptr_t) : object(nullptr), value(nullptr) {
}

db_controller::change_info::change_info(db::object object, db::value value)
    : object(std::move(object)), value(std::move(value)) {
}

#pragma mark - db_controller

db_controller::db_controller() : _manager(nullptr), _objects() {
}

void db_controller::setup(db::manager::completion_f completion) {
    this->_begin_processing();

    auto model_dict = make_objc_ptr<NSDictionary *>([]() {
        return @{
            @"entities": @{
                @"entity_a": @{
                    @"attributes": @{
                        @"age": @{@"type": @"INTEGER", @"default": @1},
                        @"name": @{@"type": @"TEXT", @"default": @"empty_name"}
                    },
                    @"relations": @{@"b": @{@"target": @"entity_b", @"many": @YES}}
                },
                @"entity_b": @{@"attributes": @{@"name": @{@"type": @"TEXT", @"default": @"empty_name"}}}
            },
            @"version": @"1.0.1"
        };
    });

    db::model model{(__bridge CFDictionaryRef)model_dict.object()};

    for (auto const &pair : model.entities()) {
        this->_objects.emplace(pair.first, db::object_vector_t{});
    }

    auto path = make_objc_ptr<NSString *>([]() {
        NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
        return [paths.firstObject stringByAppendingPathComponent:@"db.sqlite"];
    });

    this->_manager = db::manager{to_string((__bridge CFStringRef)path.object()), model};

    this->_manager.setup([weak = to_weak(shared_from_this()), completion = std::move(completion)](auto setup_result) {
        if (auto shared = weak.lock()) {
            if (setup_result) {
                shared->_update_objects([
                    weak = weak, setup_result = std::move(setup_result), completion = std::move(completion)
                ](auto update_result) {
                    if (auto shared = weak.lock()) {
                        if (update_result) {
                            shared->_end_processing();
                            shared->_subject.notify(method::objects_updated);
                        }
                        completion(std::move(update_result));
                    }
                });
            } else {
                completion(std::move(setup_result));
            }
        }
    });

    auto weak_manager = to_weak(_manager);

    this->_observer = this->_manager.subject().make_wild_card_observer([&controller = *this](auto const &context) {
        auto const &key = context.key;
        auto const &change_info = context.value;

        if (key == db::manager::method::object_changed) {
            db::object const &object = change_info.object;
            auto const &entity_name = object.entity_name();
            auto &objects = controller._objects.at(entity_name);
            if (auto idx_opt = index(objects, object)) {
                if (object.is_removed()) {
                    erase_if(objects, [&object](auto const &vec_obj) { return object == vec_obj; });
                }
                controller._subject.notify(method::object_changed,
                                           {change_info.object, db::value{static_cast<db::integer::type>(*idx_opt)}});
            } else {
                controller._subject.notify(method::object_changed);
            }
        } else if (key == db::manager::method::db_info_changed) {
            controller._subject.notify(method::db_info_changed);
        }
    });
}

void db_controller::add_temporary(entity const &entity) {
    if (this->_processing) {
        return;
    }

    auto object = this->_manager.insert_object(to_entity_name(entity));
    auto &objects = this->_objects_at(entity);

    auto idx = objects.size();
    objects.push_back(object);
    this->_subject.notify(method::object_inserted, {object, db::value{static_cast<db::integer::type>(idx)}});
}

void db_controller::add(entity const &entity) {
    if (this->_processing) {
        return;
    }

    if (!this->can_add()) {
        return;
    }

    this->_begin_processing();

    this->_manager.suspend();

    this->_manager.save([](db::manager_map_result_t result) {});

    auto inserted_object = std::make_shared<db::object>(db::null_object());

    this->_manager.insert_objects(
        [entity]() {
            auto uuid = make_cf_ref(CFUUIDCreate(nullptr));
            auto uuid_str = make_cf_ref(CFUUIDCreateString(nullptr, uuid.object()));
            db::value_map_t obj{{"name", db::value{to_string(uuid_str.object())}}};

            return db::value_map_vector_map_t{{to_entity_name(entity), {std::move(obj)}}};
        },
        [inserted_object, entity](auto insert_result) mutable {
            if (insert_result) {
                auto objects = insert_result.value().at(to_entity_name(entity));
                if (objects.size() > 0) {
                    *inserted_object = objects.at(0);
                }
            }
        });

    this->_update_objects([weak = to_weak(shared_from_this()), inserted_object, entity](auto update_result) {
        if (auto shared = weak.lock()) {
            auto idx_value = db::null_value();
            auto object = *inserted_object;

            if (object) {
                auto &objects = shared->_objects_at(entity);

                if (auto idx = index(objects, object)) {
                    idx_value = db::value{static_cast<db::integer::type>(*idx)};
                }
            }

            shared->_end_processing();
            shared->_subject.notify(method::object_inserted, {object, idx_value});
        }
    });

    this->_manager.resume();
}

void db_controller::remove(entity const &entity, std::size_t const &idx) {
    auto &objects = _objects_at(entity);

    if (objects.size() > idx) {
        if (this->_processing) {
            return;
        }

        objects.at(idx).remove();
    }
}

void db_controller::undo() {
    if (this->_processing) {
        return;
    }

    if (!this->can_undo()) {
        return;
    }

    this->_begin_processing();

    auto const undo_id = current_save_id() - 1;

    this->_manager.suspend();

    this->_manager.reset([](auto result) mutable {});

    this->_manager.revert([undo_id]() { return undo_id; }, [](auto revert_result) {});

    this->_update_objects([weak = to_weak(shared_from_this())](auto update_result) {
        if (auto shared = weak.lock()) {
            shared->_end_processing();
            shared->_subject.notify(method::objects_updated);
        }
    });

    _manager.resume();
}

void db_controller::redo() {
    if (this->_processing) {
        return;
    }

    if (!this->can_redo()) {
        return;
    }

    this->_begin_processing();

    auto const redo_id = current_save_id() + 1;

    this->_manager.suspend();

    this->_manager.reset([](auto result) mutable {});

    this->_manager.revert([redo_id]() { return redo_id; }, [](auto revert_result) {});

    this->_update_objects([weak = to_weak(shared_from_this())](auto update_result) {
        if (auto shared = weak.lock()) {
            shared->_end_processing();
            shared->_subject.notify(method::objects_updated);
        }
    });

    this->_manager.resume();
}

void db_controller::clear() {
    if (this->_processing) {
        return;
    }

    if (!can_clear()) {
        return;
    }

    this->_begin_processing();

    this->_manager.suspend();

    this->_manager.clear([](auto clear_result) {});

    this->_update_objects([weak = to_weak(shared_from_this())](auto update_result) {
        if (auto shared = weak.lock()) {
            shared->_end_processing();
            shared->_subject.notify(method::objects_updated);
        }
    });

    this->_manager.resume();
}

void db_controller::purge() {
    if (this->_processing) {
        return;
    }

    if (!this->can_purge()) {
        return;
    }

    this->_begin_processing();

    this->_manager.suspend();

    this->_manager.save([](db::manager_map_result_t result) {});

    this->_manager.purge([](auto purge_result) {});

    this->_update_objects([weak = to_weak(shared_from_this())](auto update_result) {
        if (auto shared = weak.lock()) {
            shared->_end_processing();
            shared->_subject.notify(method::objects_updated);
        }
    });

    this->_manager.resume();
}

void db_controller::save_changed() {
    if (this->_processing) {
        return;
    }

    if (!this->has_changed()) {
        return;
    }

    this->_begin_processing();

    this->_manager.suspend();

    this->_manager.save([](db::manager_map_result_t result) {});

    this->_update_objects([weak = to_weak(shared_from_this())](auto update_result) {
        if (auto shared = weak.lock()) {
            shared->_end_processing();
            shared->_subject.notify(method::objects_updated);
        }
    });

    this->_manager.resume();
}

void db_controller::cancel_changed() {
    if (this->_processing) {
        return;
    }

    if (!this->has_changed()) {
        return;
    }

    this->_begin_processing();

    this->_manager.suspend();

    this->_manager.reset([](auto result) mutable {});

    this->_update_objects([weak = to_weak(shared_from_this())](auto update_result) {
        if (auto shared = weak.lock()) {
            shared->_end_processing();
            shared->_subject.notify(method::objects_updated);
        }
    });

    this->_manager.resume();
}

bool db_controller::can_add() const {
    return !this->has_changed();
}

bool db_controller::can_undo() const {
    return !this->has_changed() && this->current_save_id() > 0;
}

bool db_controller::can_redo() const {
    return !this->has_changed() && this->current_save_id() < this->last_save_id();
}

bool db_controller::can_clear() const {
    return this->last_save_id() != 0;
}

bool db_controller::can_purge() const {
    return !this->has_changed() && this->last_save_id() > 1;
}

bool db_controller::has_changed() const {
    return this->_manager.has_changed_objects() || this->_manager.has_inserted_objects();
}

db::object const &db_controller::object(entity const &entity, std::size_t const idx) const {
    return this->_objects.at(to_entity_name(entity)).at(idx);
}

std::size_t db_controller::object_count(entity const &entity) const {
    return this->_objects.at(to_entity_name(entity)).size();
}

db::integer::type const &db_controller::current_save_id() const {
    return this->_manager.current_save_id().get<db::integer>();
}

db::integer::type const &db_controller::last_save_id() const {
    return this->_manager.last_save_id().get<db::integer>();
}

db_controller::subject_t &db_controller::subject() {
    return this->_subject;
}

bool db_controller::is_processing() const {
    return this->_processing;
}

db_controller::entity db_controller::entity_for_name(std::string const &entity_name) {
    if (entity_name == entity_name_a) {
        return entity::a;
    } else if (entity_name == entity_name_b) {
        return entity::b;
    }

    throw std::invalid_argument("invalid entity_name (" + entity_name + ").");
}

db::object_vector_t &db_controller::_objects_at(db_controller::entity const &entity) {
    return this->_objects.at(to_entity_name(entity));
}

void db_controller::_update_objects(std::function<void(db::manager_result_t)> &&completion) {
    this->_manager.suspend();

    auto results = std::make_shared<std::vector<db::manager_result_t>>();

    for (auto const &entity_pair : this->_manager.model().entities()) {
        auto const entity = this->entity_for_name(entity_pair.second.name);
        this->_update_objects(entity, [results](auto result) { results->emplace_back(std::move(result)); });
    }

    this->_manager.execute([completion = std::move(completion), results](operation const &) {
        for (auto const &result : *results) {
            if (!result) {
                completion(result);
                return;
            }
        }
        completion(db::manager_result_t{nullptr});
    });

    this->_manager.resume();
}

void db_controller::_update_objects(entity const &entity, std::function<void(db::manager_result_t)> &&completion) {
    this->_manager.suspend();

    auto const entity_name = to_entity_name(entity);

    this->_manager.fetch_objects(
        [entity_name]() {
            return db::to_fetch_option(
                db::select_option{.table = entity_name, .field_orders = {{db::object_id_field, db::order::ascending}}});
        },
        [&controller = *this, completion = std::move(completion),
         entity_name](db::manager_vector_result_t fetch_result) {
            db::manager_result_t result{nullptr};

            if (fetch_result) {
                auto &objects = fetch_result.value();
                if (objects.count(entity_name) > 0) {
                    replace(controller._objects, entity_name, std::move(objects.at(entity_name)));
                } else {
                    controller._objects.at(entity_name).clear();
                }
            } else {
                result = db::manager_result_t{std::move(fetch_result.error())};
            }

            completion(std::move(result));
        });

    this->_manager.resume();
}

void db_controller::_begin_processing() {
    this->_processing = true;

    subject().notify(method::processing_changed, {nullptr, db::value{static_cast<db::integer::type>(true)}});
}

void db_controller::_end_processing() {
    this->_processing = false;

    subject().notify(method::processing_changed, {nullptr, db::value{static_cast<db::integer::type>(false)}});
}

std::string yas::to_entity_name(db_controller::entity const &entity) {
    switch (entity) {
        case db_controller::entity::a:
            return entity_name_a;
        case db_controller::entity::b:
            return entity_name_b;
    }
}
