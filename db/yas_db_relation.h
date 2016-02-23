//
//  yas_db_relation.h
//

#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <string>

namespace yas {
namespace db {
    static std::string const src_rowid_field = "src_rowid";
    static std::string const src_obj_id_field = "src_obj_id";
    static std::string const tgt_obj_id_field = "tgt_obj_id";

    class entity;

    class relation {
       public:
        std::string const entity_name;
        std::string const name;
        std::string const target_entity_name;
        bool const many;

        std::string const table_name;

        relation(std::string const entity_name, std::string const &name, CFDictionaryRef const &dict);

        std::string sql_for_create() const;
        std::string sql_for_insert() const;
    };
}
}
