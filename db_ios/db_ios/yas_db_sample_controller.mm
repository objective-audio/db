//
//  yas_db_sample_controller.mm
//

#import <Foundation/Foundation.h>
#include "yas_cf_utils.h"
#include "yas_cf_ref.h"
#include "yas_db_sample_controller.h"

using namespace yas;
using namespace yas::sample;

namespace yas {
namespace sample {
    std::string const entity_name_a = "entity_a";
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
    _begin_processing();

    @autoreleasepool {
        NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
        NSString *path = [paths.firstObject stringByAppendingPathComponent:@"db.sqlite"];

        NSURL *modelURL = [[NSBundle mainBundle] URLForAuxiliaryExecutable:@"model.plist"];
        NSDictionary *modelDict = [NSDictionary dictionaryWithContentsOfURL:modelURL];
        db::model model{(__bridge CFDictionaryRef)modelDict};

        _manager = db::manager{to_string((__bridge CFStringRef)path), model};

        _manager.setup([weak = to_weak(shared_from_this()), completion = std::move(completion)](auto setup_result) {
            if (auto shared = weak.lock()) {
                if (setup_result) {
                    shared->_update_objects(
                        [weak = weak, setup_result = std::move(setup_result), completion = std::move(completion)](
                            auto update_result) {
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

        _observer = _manager.subject().make_wild_card_observer([&controller = *this](auto const &context) {
            auto const &key = context.key;
            auto const &change_info = context.value;

            if (key == db::manager::method::object_changed) {
                db::object const &object = change_info.object;
                if (auto idx_opt = index(controller._objects, object)) {
                    if (object.entity_name() == entity_name_a && object.is_removed()) {
                        erase_if(controller._objects, [&object](auto const &vec_obj) { return object == vec_obj; });
                    }
                    controller._subject.notify(
                        method::object_changed,
                        {change_info.object, db::value{static_cast<db::integer::type>(*idx_opt)}});
                } else {
                    controller._subject.notify(method::object_changed);
                }
            } else if (key == db::manager::method::db_info_changed) {
                controller._subject.notify(method::db_info_changed);
            }
        });
    }
}

void db_controller::add_temporary() {
    if (_processing) {
        return;
    }

    auto object = _manager.insert_object(entity_name_a);
    auto idx = _objects.size();
    _objects.push_back(object);
    _subject.notify(method::object_inserted, {object, db::value{static_cast<db::integer::type>(idx)}});
}

void db_controller::add() {
    if (_processing) {
        return;
    }

    _begin_processing();

    _manager.save([](auto result) {});
    _manager.insert_objects(
        []() {
            auto uuid = make_cf_ref(CFUUIDCreate(nullptr));
            auto uuid_str = make_cf_ref(CFUUIDCreateString(nullptr, uuid.object()));
            db::value_map obj{{"name", db::value{to_string(uuid_str.object())}}};

            return db::value_map_vector_map{{entity_name_a, {std::move(obj)}}};
        },
        [weak = to_weak(shared_from_this())](auto insert_result) {
            if (auto shared = weak.lock()) {
                shared->_update_objects([weak = weak, insert_result = std::move(insert_result)](auto update_result) {
                    if (auto shared = weak.lock()) {
                        db::value idx_value{nullptr};
                        db::object object{nullptr};

                        auto &a_objects = insert_result.value().at(entity_name_a);

                        if (a_objects.size() > 0) {
                            object = a_objects.at(0);
                            auto &objects = shared->_objects;

                            if (auto idx = index(objects, object)) {
                                idx_value = db::value{static_cast<db::integer::type>(*idx)};
                            }
                        }

                        shared->_end_processing();
                        shared->_subject.notify(method::object_inserted, {object, idx_value});
                    }
                });
            }
        });
}

void db_controller::remove(std::size_t const &idx) {
    if (_objects.size() > idx) {
        if (_processing) {
            return;
        }

        _objects.at(idx).remove();
    }
}

void db_controller::undo() {
    if (_processing) {
        return;
    }

    if (!can_undo()) {
        return;
    }

    _begin_processing();

    auto const undo_id = current_save_id() - 1;

    _manager.reset([](auto result) mutable {});
    _manager.revert([undo_id]() { return undo_id; },
                    [weak = to_weak(shared_from_this())](auto revert_result) {
                        if (auto shared = weak.lock()) {
                            shared->_update_objects([weak = weak](auto update_result) {
                                if (auto shared = weak.lock()) {
                                    shared->_end_processing();
                                    shared->_subject.notify(method::objects_updated);
                                }
                            });
                        }
                    });
}

void db_controller::redo() {
    if (_processing) {
        return;
    }

    if (!can_redo()) {
        return;
    }

    _begin_processing();

    auto const redo_id = current_save_id() + 1;

    _manager.reset([](auto result) mutable {});
    _manager.revert([redo_id]() { return redo_id; },
                    [weak = to_weak(shared_from_this())](auto revert_result) {
                        if (auto shared = weak.lock()) {
                            shared->_update_objects([weak = weak](auto update_result) {
                                if (auto shared = weak.lock()) {
                                    shared->_end_processing();
                                    shared->_subject.notify(method::objects_updated);
                                }
                            });
                        }
                    });
}

void db_controller::clear() {
    if (_processing) {
        return;
    }

    if (!can_clear()) {
        return;
    }

    _begin_processing();

    _manager.clear([weak = to_weak(shared_from_this())](auto clear_result) {
        if (auto shared = weak.lock()) {
            shared->_update_objects([weak = weak](auto update_result) {
                if (auto shared = weak.lock()) {
                    shared->_end_processing();
                    shared->_subject.notify(method::objects_updated);
                }
            });
        }
    });
}

void db_controller::purge() {
    if (_processing) {
        return;
    }

    if (!can_purge()) {
        return;
    }

    _begin_processing();

    _manager.save([](auto result) {});
    _manager.purge([weak = to_weak(shared_from_this())](auto purge_result) {
        if (auto shared = weak.lock()) {
            shared->_update_objects([weak = weak](auto update_result) {
                if (auto shared = weak.lock()) {
                    shared->_end_processing();
                    shared->_subject.notify(method::objects_updated);
                }
            });
        }
    });
}

void db_controller::save_changed() {
    if (_processing) {
        return;
    }

    if (!has_changed()) {
        return;
    }

    _begin_processing();

    _manager.save([weak = to_weak(shared_from_this())](auto save_result) {
        if (auto shared = weak.lock()) {
            shared->_update_objects([weak = weak](auto update_result) {
                if (auto shared = weak.lock()) {
                    shared->_end_processing();
                    shared->_subject.notify(method::objects_updated);
                }
            });
        }
    });
}

void db_controller::cancel_changed() {
    if (_processing) {
        return;
    }

    if (!has_changed()) {
        return;
    }

    _begin_processing();

    _manager.reset([](auto result) mutable {});
    _update_objects([weak = to_weak(shared_from_this())](auto update_result) {
        if (auto shared = weak.lock()) {
            shared->_end_processing();
            shared->_subject.notify(method::objects_updated);
        }
    });
}

bool db_controller::can_add() const {
    return !has_changed();
}

bool db_controller::can_undo() const {
    return !has_changed() && current_save_id() > 0;
}

bool db_controller::can_redo() const {
    return !has_changed() && current_save_id() < last_save_id();
}

bool db_controller::can_clear() const {
    return last_save_id() != 0;
}

bool db_controller::can_purge() const {
    return !has_changed() && last_save_id() > 1;
}

bool db_controller::has_changed() const {
    return _manager.has_changed_objects() || _manager.has_inserted_objects();
}

db::object const &db_controller::object(std::size_t const idx) const {
    return _objects.at(idx);
}

std::size_t db_controller::object_count() const {
    return _objects.size();
}

db::integer::type const &db_controller::current_save_id() const {
    return _manager.current_save_id().get<db::integer>();
}

db::integer::type const &db_controller::last_save_id() const {
    return _manager.last_save_id().get<db::integer>();
}

db_controller::subject_t &db_controller::subject() {
    return _subject;
}

bool db_controller::is_processing() const {
    return _processing;
}

void db_controller::_update_objects(std::function<void(db::manager::result_t)> &&completion) {
    _manager.fetch_objects(
        []() {
            return db::select_option{.table = entity_name_a,
                                     .field_orders = {{db::object_id_field, db::order::ascending}}};
        },
        [&controller = *this, completion = std::move(completion)](auto fetch_result) {
            db::manager::result_t result{nullptr};

            if (fetch_result) {
                auto &objects = fetch_result.value();
                if (objects.count(entity_name_a) > 0) {
                    controller._objects = std::move(objects.at(entity_name_a));
                } else {
                    controller._objects.clear();
                }
            } else {
                result = db::manager::result_t{std::move(fetch_result.error())};
            }

            completion(std::move(result));
        });
}

void db_controller::_begin_processing() {
    _processing = true;

    subject().notify(method::processing_changed, {nullptr, db::value{static_cast<db::integer::type>(true)}});
}

void db_controller::_end_processing() {
    _processing = false;

    subject().notify(method::processing_changed, {nullptr, db::value{static_cast<db::integer::type>(false)}});
}
