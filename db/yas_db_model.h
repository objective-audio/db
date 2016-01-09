//
//  yas_db_model.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <memory>
#include <string>
#include "yas_base.h"
#include "yas_db_entity.h"
#include "yas_version.h"

namespace yas {
namespace db {
    class model : public base {
        using super_class = base;

       public:
        using entities_map = std::unordered_map<std::string, entity>;

        model(CFDictionaryRef const &dict);

        yas::version const &version() const;
        entities_map const &entities() const;

       private:
        class impl;
    };
}
}
