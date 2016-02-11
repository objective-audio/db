//
//  yas_db_utils.h
//

#pragma once

#include "yas_db_object.h"

namespace yas {
namespace db {
    class database;
    class select_option;

    using select_result = result<value_map_vector, error>;
    using select_single_result = result<value_map, std::nullptr_t>;

    update_result create_table(database &db, std::string const &table_name, std::vector<std::string> const &fields);
    update_result alter_table(database &db, std::string const &table_name, std::string const &field);
    update_result drop_table(database &db, std::string const &table_name);

    update_result create_index(database &db, std::string const &index_name, std::string const &table_name,
                               std::vector<std::string> const &fields);
    update_result drop_index(database &db, std::string const &index_name);

    update_result begin_transaction(database &db);
    update_result begin_deferred_transaction(database &db);
    update_result commit(database &db);
    update_result rollback(database &db);

#if SQLITE_VERSION_NUMBER >= 3007000
    update_result start_save_point(database &db, std::string const &name);
    update_result release_save_point(database &db, std::string const &name);
    update_result rollback_save_point(database &db, std::string const &name);

    update_result in_save_point(database &db, std::function<void(bool &rollback)> const function);
#endif

    bool table_exists(database const &db, std::string const &table_name);
    bool index_exists(database const &db, std::string const &index_name);
    row_set get_schema(database const &db);
    row_set get_table_schema(database const &db, std::string const &table_name);
    row_set get_index_schema(database const &db, std::string const &index_name);
    bool column_exists(database const &db, std::string column_name, std::string table_name);

    select_result select(database const &db, std::string const &table_name, select_option const &option = {});
    select_result select_last(database const &db, std::string const &table_name, value const &save_id = nullptr,
                              select_option option = {});
    select_result select_undo(database const &db, std::string const &table_name, integer::type const revert_save_id,
                              integer::type const current_save_id);
    select_result select_redo(database const &db, std::string const &table_name, integer::type const revert_save_id,
                              integer::type const current_save_id);
    select_result select_revert(database const &db, std::string const &table_name, integer::type const revert_save_id,
                                integer::type const current_save_id);

    select_single_result select_single(database const &db, std::string const &table_name, select_option option = {});
    select_single_result select_db_info(database const &db);

    value max(database const &db, std::string const &table_name, std::string const &field);

    std::vector<const_object> get_const_relation_objects(const_object const &object,
                                                         const_object_map_map const &objects,
                                                         std::string const &rel_name);
    db::const_object get_const_relation_object(const_object const &object, const_object_map_map const &objects,
                                               std::string const &rel_name, std::size_t const idx);

    template <typename T>
    db::integer_set_map relation_ids(T const &objects) {
        db::integer_set_map rel_ids;

        for (auto const &entity_pair : objects) {
            for (auto const &object : entity_pair.second) {
                auto obj_rel_ids = object.relation_ids_for_fetch();
                for (auto &obj_rel_pair : obj_rel_ids) {
                    auto const &entity_name = obj_rel_pair.first;
                    if (rel_ids.count(entity_name) == 0) {
                        rel_ids.emplace(std::make_pair(entity_name, integer_set{}));
                    }

                    for (auto &tgt_id : obj_rel_pair.second) {
                        rel_ids.at(entity_name).emplace(tgt_id);
                    }
                }
            }
        }

        return rel_ids;
    }
}
db::object_map_map to_object_map_map(db::object_vector_map vec);
db::object_map to_object_map(db::object_vector vec);
}
