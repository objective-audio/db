//
//  yas_db_ptr.h
//

#pragma once

#include <memory>
#include <optional>

namespace yas::db {
class database;
class info;
class manager;
class row_set;
class statement;
class object_id;
class const_object;
class object;

class closable;
class row_set_observable;
class db_settable;

using database_ptr = std::shared_ptr<database>;
using database_wptr = std::weak_ptr<database>;
using manager_ptr = std::shared_ptr<manager>;
using manager_wptr = std::weak_ptr<manager>;
using row_set_ptr = std::shared_ptr<row_set>;
using row_set_wptr = std::weak_ptr<row_set>;
using statement_ptr = std::shared_ptr<statement>;
using object_id_ptr = std::shared_ptr<object_id>;
using const_object_ptr = std::shared_ptr<const_object>;
using object_ptr = std::shared_ptr<object>;
using object_wptr = std::weak_ptr<object>;

using closable_ptr = std::shared_ptr<closable>;
using row_set_observable_ptr = std::shared_ptr<row_set_observable>;
using db_settable_ptr = std::shared_ptr<db_settable>;

using info_opt = std::optional<info>;
}  // namespace yas::db
