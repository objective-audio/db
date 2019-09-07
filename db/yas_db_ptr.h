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

using database_ptr = std::shared_ptr<database>;
using database_wptr = std::weak_ptr<database>;
using manager_ptr = std::shared_ptr<manager>;
using manager_wptr = std::weak_ptr<manager>;
using row_set_ptr = std::shared_ptr<row_set>;
using row_set_wptr = std::weak_ptr<row_set>;
using statement_ptr = std::shared_ptr<statement>;

using info_opt = std::optional<info>;
}  // namespace yas::db
