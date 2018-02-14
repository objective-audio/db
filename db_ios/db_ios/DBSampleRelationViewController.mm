//
//  DBSampleRelationViewController.mm
//

#import "DBSampleRelationViewController.h"
#import "DBSampleObjectSelectionViewController.h"
#import "DBSampleObjectNormalCell.h"
#import "yas_objc_cast.h"
#import "yas_objc_ptr.h"
#import "yas_objc_unowned.h"
#import "yas_cf_utils.h"

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
}

@implementation DBSampleRelationViewController {
    std::weak_ptr<db_controller> _db_controller;
    std::experimental::optional<db::object> _db_object;
    std::string _rel_name;

    std::vector<base> _observers;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = (__bridge NSString *)to_cf_object(_rel_name);
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if (auto viewController = objc_cast<DBSampleObjectSelectionViewController>(segue.destinationViewController)) {
        auto const &relation = _db_object->entity().relations.at(_rel_name);

        auto unowned_self = make_objc_ptr([[YASUnownedObject<typeof(self)> alloc] initWithObject:self]);

        auto selected_handler = [unowned_self](db::object const &rel_object) {
            auto self = [unowned_self.object() object];
            self.db_object.add_relation_object(self.relation_name, rel_object);
        };

        [viewController set_db_controller:_db_controller
                                   entity:db_controller::entity_for_name(relation.target_entity_name)
                         selected_handler:std::move(selected_handler)];
    }
}

- (void)set_db_controller:(std::weak_ptr<sample::db_controller>)controller
                   object:(db::object)object
             relationName:(std::string)rel_name {
    _db_controller = std::move(controller);
    *_db_object = std::move(object);
    _rel_name = std::move(rel_name);

    auto unowned_self = make_objc_ptr([[YASUnownedObject<typeof(self)> alloc] initWithObject:self]);

    auto rel_changed_handler = [unowned_self, rel_name = _rel_name](auto const &context) {
        db::object::change_info const &info = context.value;
        if (info.name == rel_name) {
            if (auto self = unowned_self.object().object) {
                auto const &rel_info = info.relation_change_info();
                auto indexPaths = [[NSMutableArray<NSIndexPath *> alloc] init];
                for (auto const &idx : rel_info.indices) {
                    [indexPaths addObject:[NSIndexPath indexPathForRow:idx inSection:NSInteger(rel_section::objects)]];
                }

                switch (rel_info.reason) {
                    case db::object::change_reason::inserted: {
                        [self.tableView insertRowsAtIndexPaths:indexPaths
                                              withRowAnimation:UITableViewRowAnimationAutomatic];
                    } break;

                    case db::object::change_reason::removed: {
                        [self.tableView deleteRowsAtIndexPaths:indexPaths
                                              withRowAnimation:UITableViewRowAnimationAutomatic];
                    } break;

                    default: { [self.tableView reloadData]; } break;
                }
            }
        }
    };

    auto observer = _db_object->subject().make_observer(db::object::method::relation_changed, rel_changed_handler);

    _observers.emplace_back(std::move(observer));
}

- (db::object &)db_object {
    return *_db_object;
}

- (std::string const &)relation_name {
    return _rel_name;
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
            return [self db_object].relation_size(_rel_name);
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
                if (auto const rel_obj = db_obj.relation_object_at(_rel_name, indexPath.row)) {
                    auto const &obj_id = rel_obj.object_id();
                    auto const &name = rel_obj.attribute_value("name");
                    std::string const title = "object_id:" + to_string(obj_id) + " name:" + to_string(name);
                    [normalCell setupWithTitle:title];
                } else {
                    auto const &rel_id = db_obj.relation_id(_rel_name, indexPath.row);
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
            _db_object->remove_relation_at(_rel_name, indexPath.row);
        }
    }
}

@end
