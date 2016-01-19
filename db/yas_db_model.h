//
//  yas_db_model.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <memory>
#include <string>
#include "yas_base.h"

namespace yas {
class version;

namespace db {
    class entity;

    class model : public base {
        using super_class = base;

       public:
        using entity_map = std::unordered_map<std::string, entity>;

        model(CFDictionaryRef const &dict);

        yas::version const &version() const;
        entity_map const &entities() const;

       private:
        class impl;
    };
}
}
