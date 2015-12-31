//
//  yas_db_manager.cpp
//

#include "yas_db_manager.h"

using namespace yas;

struct db::manager::impl : public base::impl {
    database database;
    operation_queue queue;

    impl(std::string const &path) : database(path), queue() {
        database.open();
    }
};

db::manager::manager(std::string const &path) : super_class(std::make_unique<impl>(path)) {
}

db::manager::manager(std::nullptr_t) : super_class(nullptr) {
}

std::string const &db::manager::database_path() const {
    return impl_ptr<impl>()->database.database_path();
}

void db::manager::execute(execution_f &&db_execution) {
    auto ip = impl_ptr<impl>();

    auto execution = [db_execution = std::move(db_execution), db = ip->database](operation const &op) mutable {
        if (!op.is_canceled()) {
            db_execution(db, op);
        }
    };

    ip->queue.add_operation(operation{std::move(execution)});
}