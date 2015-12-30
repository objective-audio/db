//
//  yas_db_manager.h
//

#pragma once

#include "yas_base.h"
#include "yas_db_database.h"
#include "yas_operation.h"

namespace yas {
namespace db {
    class manager : public base {
        using super_class = base;

       public:
        using execution_f = std::function<void(database &, operation const &)>;

        explicit manager(std::string const &path);
        manager(std::nullptr_t);

        std::string const &database_path() const;

        void execute(execution_f &&execution);

       private:
        class impl;
    };
}
}
