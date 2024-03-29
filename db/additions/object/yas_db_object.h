//
//  yas_db_object.h
//

#pragma once

#include <db/yas_db_additional_protocol.h>
#include <db/yas_db_entity.h>
#include <db/yas_db_object_event.h>

#include <deque>
#include <observing/yas_observing_umbrella.hpp>
#include <set>
#include <unordered_map>

namespace yas::db {
struct const_object {
    [[nodiscard]] db::entity const &entity() const;
    [[nodiscard]] std::string const &entity_name() const;

    [[nodiscard]] db::value const &attribute_value(std::string const &attr_name) const;

    [[nodiscard]] db::id_vector_map_t const &all_relation_ids() const;
    [[nodiscard]] db::id_vector_t relation_ids(std::string const &rel_name) const;
    [[nodiscard]] db::object_id const &relation_id(std::string const &rel_name, std::size_t const idx) const;
    [[nodiscard]] std::size_t relation_size(std::string const &rel_name) const;

    [[nodiscard]] db::object_id const &object_id() const;
    [[nodiscard]] db::value const &save_id() const;
    [[nodiscard]] db::value const &action() const;

    [[nodiscard]] bool is_inserted() const;
    [[nodiscard]] bool is_updated() const;
    [[nodiscard]] bool is_removed() const;

    [[nodiscard]] static const_object_ptr make_shared(db::entity const &entity, db::object_data const &obj_data);

   protected:
    db::entity _entity;
    db::value_map_t _attributes;
    db::id_vector_map_t _relations;
    db::object_id _identifier;

    const_object(db::entity const &entity, db::object_data const &obj_data);
    const_object(db::entity const &entity, db::object_id &&identifier);

    void _clear();
    bool _is_equal_to_action(std::string const &) const;
    void _update_identifier(db::object_data const &);
    void _validate_attribute_name(std::string const &) const;
    void _validate_relation_name(std::string const &) const;
    void _validate_relation_id(db::object_id const &) const;
    void _validate_relation_ids(db::id_vector_t const &) const;

   private:
    void _load_data(db::object_data const &);
    void _update_identifier(db::value stable);
    void _validate_temporary_id(db::object_id const &other_object_id) const;
};

struct object final : const_object, manageable_object {
    ~object();

    using observing_handler_f = std::function<void(object_event const &)>;
    [[nodiscard]] observing::syncable observe(observing_handler_f &&);

    void set_attribute_value(std::string const &attr_name, db::value const &value);

    void set_relation_ids(std::string const &rel_name, db::id_vector_t const &relation_ids);
    void add_relation_id(std::string const &rel_name, db::object_id const &relation_id);
    void insert_relation_id(std::string const &rel_name, db::object_id const &relation_id, std::size_t const idx);
    void remove_relation_id(std::string const &rel_name, db::object_id const &relation_id);
    void set_relation_objects(std::string const &rel_name, db::object_vector_t const &rel_objects);
    void add_relation_object(std::string const &rel_name, db::object_ptr const &rel_object);
    void insert_relation_object(std::string const &rel_name, db::object_ptr const &rel_object, std::size_t const idx);
    void remove_relation_object(std::string const &rel_name, db::object_ptr const &rel_object);
    void remove_relation_at(std::string const &rel_name, std::size_t const idx);
    void remove_all_relations(std::string const &rel_name);

    db::object_status status() const;

    void remove();

    bool is_temporary() const;

    db::object_data save_data(db::object_id_pool &) const;

    static object_ptr make_shared(db::entity const &);

   private:
    object(db::entity const &entity);

    enum db::object_status _status = db::object_status::invalid;
    observing::fetcher_ptr<object_event> _fetcher = nullptr;
    db::object_wptr _weak_object;

    void _prepare(object_ptr const &);

    void set_status(db::object_status const &) override;
    void load_insertion_data() override;
    void load_data(db::object_data const &obj_data, bool const force) override;
    void load_save_id(db::value const &save_id) override;
    void clear_data() override;

    void _clear();
    void _set_attribute_value(std::string const &attr_name, db::value const &value, bool const loading);
    void _set_relation_ids(std::string const &rel_name, db::id_vector_t const &relation_ids,
                           bool const loading = false);
    void _set_update_action();
};

db::value const &insert_action_value();
db::value const &update_action_value();
db::value const &remove_action_value();
}  // namespace yas::db

namespace yas {
std::string to_string(db::object_status const &);
}
