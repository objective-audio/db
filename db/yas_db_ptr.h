//
//  yas_db_ptr.h
//

#pragma once

#include <memory>
#include <optional>

namespace yas::db {
class database;
class info;

using database_ptr = std::shared_ptr<database>;
using database_wptr = std::weak_ptr<database>;
using info_opt = std::optional<info>;
}  // namespace yas::db
