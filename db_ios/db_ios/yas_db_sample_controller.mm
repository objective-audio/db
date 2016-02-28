//
//  yas_db_sample_controller.mm
//

#import <Foundation/Foundation.h>
#include "yas_cf_utils.h"
#include "yas_db.h"
#include "yas_db_sample_controller.h"

using namespace yas;
using namespace yas::sample;

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
                                    shared->_subject.notify(objects_did_update_key);
                                }
                                completion(std::move(update_result));
                            }
                        });
                } else {
                    completion(std::move(setup_result));
                }
            }
        });
    }
}

void db_controller::add() {
    if (_processing) {
        return;
    }

    _begin_processing();

    _manager.insert_objects(
        []() {
            CFUUIDRef cf_uuid = CFUUIDCreate(nullptr);
            CFStringRef cf_str = CFUUIDCreateString(nullptr, cf_uuid);
            CFRelease(cf_uuid);
            db::value_map obj{{"name", db::value{to_string(cf_str)}}};
            CFRelease(cf_str);

            return db::value_map_vector_map{{"entity_a", {std::move(obj)}}};
        },
        [weak = to_weak(shared_from_this())](auto insert_result) {
            if (auto shared = weak.lock()) {
                shared->_update_objects([weak = weak, insert_result = std::move(insert_result)](auto update_result) {
                    if (auto shared = weak.lock()) {
                        db::value idx_value{nullptr};

                        auto &a_objects = insert_result.value().at("entity_a");
                        if (a_objects.size() > 0) {
                            auto &target_obj = a_objects.at(0);
                            auto &objects = shared->_objects;
                            auto it = std::find_if(objects.begin(), objects.end(),
                                                   [&target_obj](auto const &obj) { return target_obj == obj; });
                            if (it != objects.end()) {
                                auto distance = std::distance(objects.begin(), it);
                                idx_value = db::value{static_cast<db::integer::type>(distance)};
                            }
                        }

                        shared->_end_processing();
                        shared->_subject.notify(object_did_insert_key, idx_value);
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

        _begin_processing();

        auto &object = _objects.at(idx);
        object.remove();

        _manager.save([weak = to_weak(shared_from_this()), idx](auto save_result) {
            if (auto shared = weak.lock()) {
                shared->_update_objects([weak = weak, idx](auto update_result) {
                    if (auto shared = weak.lock()) {
                        shared->_end_processing();
                        shared->subject().notify(object_did_remove_key, db::value{static_cast<db::integer::type>(idx)});
                    }
                });
            }
        });
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

    _manager.revert([undo_id]() { return undo_id; },
                    [weak = to_weak(shared_from_this())](auto revert_result) {
                        if (auto shared = weak.lock()) {
                            shared->_update_objects([weak = weak](auto update_result) {
                                if (auto shared = weak.lock()) {
                                    shared->_end_processing();
                                    shared->_subject.notify(objects_did_update_key);
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

    _manager.revert([redo_id]() { return redo_id; },
                    [weak = to_weak(shared_from_this())](auto revert_result) {
                        if (auto shared = weak.lock()) {
                            shared->_update_objects([weak = weak](auto update_result) {
                                if (auto shared = weak.lock()) {
                                    shared->_end_processing();
                                    shared->_subject.notify(objects_did_update_key);
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
                    shared->_subject.notify(objects_did_update_key);
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

    _manager.purge([weak = to_weak(shared_from_this())](auto purge_result) {
        if (auto shared = weak.lock()) {
            shared->_update_objects([weak = weak](auto update_result) {
                if (auto shared = weak.lock()) {
                    shared->_end_processing();
                    shared->_subject.notify(objects_did_update_key);
                }
            });
        }
    });
}

void db_controller::save() {
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
                    shared->_subject.notify(objects_did_update_key);
                }
            });
        }
    });
}

void db_controller::cancel() {
    if (_processing) {
        return;
    }

    if (!has_changed()) {
        return;
    }

    _begin_processing();

    _update_objects([weak = to_weak(shared_from_this())](auto update_result) {
        if (auto shared = weak.lock()) {
            shared->_end_processing();
            shared->_subject.notify(objects_did_update_key);
        }
    });
}

bool db_controller::can_undo() const {
    return current_save_id() > 0;
}

bool db_controller::can_redo() const {
    return current_save_id() < last_save_id();
}

bool db_controller::can_clear() const {
    return last_save_id() != 0;
}

bool db_controller::can_purge() const {
    return last_save_id() > 1;
}

bool db_controller::has_changed() const {
    return _manager.has_changed_objects();
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

subject<db::value> &db_controller::subject() {
    return _subject;
}

bool db_controller::is_processing() const {
    return _processing;
}

void db_controller::send_object_did_change() const {
    _subject.notify(object_did_change_key);
}

void db_controller::_update_objects(std::function<void(db::manager::result_t)> &&completion) {
    _manager.fetch_objects(
        []() {
            return db::select_option{.table = "entity_a",
                                     .field_orders = {{db::object_id_field, db::order::ascending}}};
        },
        [&controller = *this, completion = std::move(completion)](auto fetch_result) {
            db::manager::result_t result{nullptr};

            if (fetch_result) {
                auto &objects = fetch_result.value();
                if (objects.count("entity_a") > 0) {
                    controller._objects = std::move(objects.at("entity_a"));
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

    subject().notify(processing_did_change_key, db::value{static_cast<db::integer::type>(true)});
}

void db_controller::_end_processing() {
    _processing = false;

    subject().notify(processing_did_change_key, db::value{static_cast<db::integer::type>(false)});
}
