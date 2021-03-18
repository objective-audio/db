//
//  DBSampleRelationViewController.mm
//

#import "DBSampleRelationViewController.h"
#import "DBSampleObjectNormalCell.h"
#import "DBSampleObjectSelectionViewController.h"
#import <cpp_utils/yas_cf_utils.h>
#import <cpp_utils/yas_objc_cast.h>
#import <cpp_utils/yas_objc_ptr.h>
#import <objc_utils/yas_objc_unowned.h>

using namespace yas;
using namespace yas::sample;

namespace yas::sample {
enum class rel_section : std::size_t {
    control,
    objects,

    last = objects,
};

enum class rel_control_row : std::size_t {
    add,

    last = add,
};

using rel_section_type_t = std::underlying_type<rel_section>::type;
using rel_control_row_type_t = std::underlying_type<rel_control_row>::type;

static NSString *const rel_normal_cell_id = @"NormalCell";
static NSString *const rel_control_cell_id = @"ControlCell";
}

namespace yas {
rel_section_type_t to_idx(rel_section const &section) {
    return rel_section_type_t(section);
}

rel_control_row_type_t to_idx(rel_control_row const &row) {
    return rel_control_row_type_t(row);
}

objc_ptr<NSArray<NSIndexPath *> *> to_index_paths(std::vector<std::size_t> const &indices) {
    auto index_paths = objc_ptr_with_move_object([[NSMutableArray<NSIndexPath *> alloc] init]);
    for (auto const &idx : indices) {
        [index_paths.object() addObject:[NSIndexPath indexPathForRow:idx inSection:NSInteger(rel_section::objects)]];
    }
    return objc_ptr_with_move_object<NSArray<NSIndexPath *> *>([index_paths.object() copy]);
}
}

@implementation DBSampleRelationViewController {
    std::weak_ptr<db_controller> _db_controller;
    std::optional<db::object_ptr> _db_object;
    std::string _rel_name;

    observing::canceller_pool _pool;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = (__bridge NSString *)to_cf_object(self->_rel_name);
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if (auto viewController = objc_cast<DBSampleObjectSelectionViewController>(segue.destinationViewController)) {
        auto const &relation = (*self->_db_object)->entity().relations.at(self->_rel_name);

        auto unowned_self = objc_ptr_with_move_object([[YASUnownedObject<typeof(self)> alloc] initWithObject:self]);

        auto selected_handler = [unowned_self](db::object_ptr const &rel_object) {
            auto self = [unowned_self.object() object];
            self.db_object->add_relation_object(self.relation_name, rel_object);
        };

        [viewController set_db_controller:self->_db_controller
                                   entity:db_controller::entity_for_name(relation.target)
                         selected_handler:std::move(selected_handler)];
    }
}

- (void)set_db_controller:(std::weak_ptr<sample::db_controller>)controller
                   object:(db::object_ptr const &)object
             relationName:(std::string)rel_name {
    self->_db_controller = std::move(controller);
    self->_db_object = object;
    self->_rel_name = std::move(rel_name);

    auto unowned_self = objc_ptr_with_move_object([[YASUnownedObject<typeof(self)> alloc] initWithObject:self]);

        object->observe([unowned_self, rel_name = self->_rel_name](db::object_event const &event) {
                auto self = unowned_self.object().object;
                if (!self) {
                    return;
                }

                switch (event.type()) {
                    case db::object_event_type::relation_inserted: {
                        auto const &inserted_event = event.get<db::object_relation_inserted_event>();
                        if (inserted_event.name != rel_name) {
                            return;
                        }
                        [self.tableView insertRowsAtIndexPaths:to_index_paths(inserted_event.indices).object()
                                              withRowAnimation:UITableViewRowAnimationAutomatic];
                    } break;

                    case db::object_event_type::relation_removed: {
                        auto const &removed_event = event.get<db::object_relation_removed_event>();
                        if (removed_event.name != rel_name) {
                            return;
                        }
                        [self.tableView deleteRowsAtIndexPaths:to_index_paths(removed_event.indices).object()
                                              withRowAnimation:UITableViewRowAnimationAutomatic];
                    } break;

                    case db::object_event_type::relation_replaced: {
                        auto const &replaced_event = event.get<db::object_relation_replaced_event>();
                        if (replaced_event.name != rel_name) {
                            return;
                        }
                        [self.tableView reloadData];
                    } break;

                    default:
                        break;
                }
        }, false)->add_to(self->_pool);
}

- (db::object_ptr &)db_object {
    return *self->_db_object;
}

- (std::string const &)relation_name {
    return self->_rel_name;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return to_idx(rel_section::last) + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (rel_section(section)) {
        case rel_section::control:
            return to_idx(rel_control_row::last) + 1;

        case rel_section::objects:
            return [self db_object]->relation_size(self->_rel_name);
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (rel_section(section)) {
        case rel_section::objects:
            return @"objects";

        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;

    switch (rel_section(indexPath.section)) {
        case rel_section::control: {
            switch (rel_control_row(indexPath.row)) {
                case rel_control_row::add: {
                    cell = [tableView dequeueReusableCellWithIdentifier:sample::rel_control_cell_id
                                                           forIndexPath:indexPath];
                    if (auto controlCell = objc_cast<DBSampleObjectNormalCell>(cell)) {
                        [controlCell setupWithTitle:"add"];
                    }
                } break;

                default:
                    break;
            }
        } break;

        case rel_section::objects: {
            cell = [tableView dequeueReusableCellWithIdentifier:sample::rel_normal_cell_id forIndexPath:indexPath];
            if (auto normalCell = objc_cast<DBSampleObjectNormalCell>(cell)) {
                auto const &db_obj = [self db_object];
                if (auto const rel_obj =
                        self->_db_controller.lock()->relation_object_at(db_obj, self->_rel_name, indexPath.row)) {
                    auto const &obj_id = (*rel_obj)->object_id();
                    auto const &name = (*rel_obj)->attribute_value("name");
                    std::string const title = "object_id:" + to_string(obj_id) + " name:" + to_string(name);
                    [normalCell setupWithTitle:title];
                } else {
                    auto const &rel_id = db_obj->relation_id(self->_rel_name, indexPath.row);
                    std::string const title = "object_id" + to_string(rel_id) + " (null)";
                    [normalCell setupWithTitle:title];
                }
            }
        } break;
    }

    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (rel_section(indexPath.section)) {
        case rel_section::objects:
            return YES;

        default:
            return NO;
    }
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        if (rel_section(indexPath.section) == rel_section::objects) {
            [self db_object]->remove_relation_at(self->_rel_name, indexPath.row);
        }
    }
}

@end
