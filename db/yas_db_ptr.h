//
//  yas_db_ptr.h
//

#pragma once

#include <memory>

namespace yas::db {
class database;

using database_ptr = std::shared_ptr<database>;
using database_wptr = std::weak_ptr<database>;
}  // namespace yas::db
