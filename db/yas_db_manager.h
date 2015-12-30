//
//  yas_db_manager.h
//

#pragma once

#include "yas_base.h"

namespace yas {
namespace db {
    class manager : public base {
        using super_class = base;

        explicit manager(std::string const &path);
        manager(std::nullptr_t);

       public:
       private:
        class impl;
    };
}
}
