//
//  yas_db_manager.h
//

#pragma once

#include "yas_base.h"
#include "yas_db_database.h"
#include "yas_db_model.h"
#include "yas_db_object.h"
#include "yas_operation.h"

namespace yas {
namespace db {
    static auto constexpr info_table = "db_info";
    static auto constexpr version_field = "version";

    class manager : public base {
        using super_class = base;

       public:
        enum class setup_error {
            unknown,
            begin_transaction_failed,
            select_info_failed,
            update_info_failed,
            version_not_found,
            invalid_version_text,
            alter_entity_table_failed,
            create_info_table_failed,
            insert_info_failed,
            create_entity_table_failed,
            create_relation_table_failed
        };
        enum class insert_error { unknown, insert_failed, select_failed, save_id_not_found, update_save_id_failed };

        using setup_result = result<std::nullptr_t, setup_error>;
        using insert_result = result<std::vector<db::object>, insert_error>;

        using setup_completion_f = std::function<void(setup_result const &)>;
        using insert_completion_f = std::function<void(insert_result const &)>;
        using execution_f = std::function<void(database &, operation const &)>;

        explicit manager(std::string const &db_path, model const &model);
        manager(std::nullptr_t);

        void setup(setup_completion_f &&completion);

        std::string const &database_path() const;
        const database &database() const;
        const model &model() const;
        db::integer::type save_id() const;

        void execute(execution_f &&execution);

        void insert_objects(std::string const &entity_name, std::size_t const count, insert_completion_f &&completion);

        db::object const &cached_object(std::string const &entity_name, db::integer::type object_id) const;

       private:
        class impl;
    };
}
}
