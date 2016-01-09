//
//  yas_db_manager.h
//

#pragma once

#include "yas_base.h"
#include "yas_db_database.h"
#include "yas_db_model.h"
#include "yas_operation.h"

namespace yas {
namespace db {
    class manager : public base {
        using super_class = base;

       public:
        using setup_completion_f = std::function<void(bool const)>;
        using execution_f = std::function<void(database &, operation const &)>;

        explicit manager(std::string const &db_path, model &&model);
        manager(std::nullptr_t);

        void setup(setup_completion_f &&completion);

        std::string const &database_path() const;
        const database &database() const;
        const model &model() const;

        void execute(execution_f &&execution);

       private:
        class impl;
    };
}
}
