//
//  DBSampleTopViewController.mm
//

#import "DBSampleTopViewController.h"
#import "DBSampleObjectViewController.h"
#import "yas_cf_utils.h"
#import "yas_db.h"
#import "yas_objc_ptr.h"
#import "yas_objc_unowned.h"
#import "yas_sample_db_controller.h"

using namespace yas;
using namespace yas::sample;

namespace yas::sample {
enum class top_section : std::size_t {
    actions,
    infos,
    objects_a,
    objects_b,

    last = objects_b,
};

enum class top_action_row : std::size_t {
    create_a,
    create_b,
    insert_a,
    insert_b,
    undo,
    redo,
    clear,
    purge,
    save_changed,
    cancel_changed,

    last = cancel_changed,
};

enum class top_info_row : std::size_t {
    save_id,
    object_count,

    last = object_count,
};

using top_section_type_t = std::underlying_type_t<top_section>;
using top_action_row_type_t = std::underlying_type_t<top_action_row>;
using top_info_row_type_t = std::underlying_type_t<top_info_row>;
}

namespace yas {
top_section_type_t to_idx(sample::top_section const &section) {
    return sample::top_section_type_t(section);
}

top_action_row_type_t to_idx(sample::top_action_row const &row) {
    return sample::top_action_row_type_t(row);
}

top_info_row_type_t to_idx(sample::top_info_row const &row) {
    return sample::top_info_row_type_t(row);
}
}

@interface DBSampleTopViewController ()

@end

@implementation DBSampleTopViewController {
    std::shared_ptr<db_controller> _db_controller;
    std::vector<db_controller::observer_t> _observers;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.rightBarButtonItem = self.editButtonItem;

    _db_controller = std::make_shared<db_controller>();

    auto unowned_self = make_objc_ptr([[YASUnownedObject<DBSampleTopViewController *> alloc] initWithObject:self]);

    auto proccessing_observer = _db_controller->subject().make_observer(
        db_controller::method::processing_changed, [unowned_self](auto const &context) {
            db_controller::change_info const &info = context.value;

            auto controller = [unowned_self.object() object];
            if (info.value.get<db::integer>()) {
                controller.title = @"Processing...";
            } else {
                controller.title = nil;
            }
        });

    _observers.emplace_back(std::move(proccessing_observer));

    _db_controller->setup([unowned_self](auto result) {
        auto controller = [unowned_self.object() object];

        if (result) {
            [controller setupObserversAfterSetup];
            [controller updateTable];
        } else {
            CFStringRef cf_string = to_cf_object(to_string(result.error()));
            [controller showErrorAlertWithTitle:@"Setup Error" message:(__bridge NSString *)cf_string];
        }
    });
}

- (void)setupObserversAfterSetup {
    auto unowned_self = make_objc_ptr([[YASUnownedObject<DBSampleTopViewController *> alloc] initWithObject:self]);

    auto observer = _db_controller->subject().make_wild_card_observer([unowned_self](auto const &context) {
        auto const &key = context.key;
        db_controller::change_info const &info = context.value;

        auto controller = [unowned_self.object() object];

        switch (key) {
            case db_controller::method::db_info_changed: {
                [controller updateTableForInfo:top_info_row::save_id];
            } break;

            case db_controller::method::all_objects_updated: {
                [controller updateTable];
            } break;

            case db_controller::method::object_created: {
                auto const &object = info.object;
                auto const entity = db_controller::entity_for_name(object.entity_name());
                [controller updateTableForInsertedRow:NSInteger(info.value.get<db::integer>()) entity:entity];
            } break;

            case db_controller::method::object_changed: {
                auto const &index = info.value.get<db::integer>();
                auto const &object = info.object;

                if (info.value) {
                    auto const entity = db_controller::entity_for_name(object.entity_name());
                    [controller updateTableObjectCellAtIndex:NSInteger(index) entity:entity];
                } else {
                    [controller updateTableObjects];
                }

                [controller updateTableActions];
            } break;

            case db_controller::method::object_removed: {
                auto const &index = info.value.get<db::integer>();
                auto const &object = info.object;

                auto const entity = db_controller::entity_for_name(object.entity_name());
                [controller updateTableForDeletedRow:NSInteger(index) entity:entity];

                [controller updateTableActions];
            } break;

            default:
                break;
        }
    });

    _observers.emplace_back(std::move(observer));
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.destinationViewController isKindOfClass:[DBSampleObjectViewController class]]) {
        DBSampleObjectViewController *controller = segue.destinationViewController;

        NSIndexPath *indexPath = [self.tableView indexPathForCell:sender];
        if (indexPath.row != NSNotFound) {
            auto const entity = [[self class] entityForSection:top_section(indexPath.section)];
            [controller set_db_controller:_db_controller
                                db_object:_db_controller->object(entity, static_cast<std::size_t>(indexPath.row))];
        }
    }
}

- (void)updateTable {
    [self.tableView reloadData];
}

- (void)updateTableActions {
    for (auto &idx : make_each_index(std::size_t(to_idx(top_action_row::last) + 1))) {
        [self updateTableForAction:top_action_row(idx)];
    }
}

- (void)updateTableForAction:(top_action_row)row {
    UITableViewCell *cell = [self.tableView
        cellForRowAtIndexPath:[NSIndexPath indexPathForRow:to_idx(row) inSection:to_idx(top_section::actions)]];
    [self updateActionCell:cell atRow:row];
}

- (void)updateTableInfos {
    [self updateTableForInfo:top_info_row::save_id];
    [self updateTableForInfo:top_info_row::object_count];
}

- (void)updateTableForInfo:(top_info_row const &)row {
    UITableViewCell *cell = [self.tableView
        cellForRowAtIndexPath:[NSIndexPath indexPathForRow:to_idx(row) inSection:to_idx(top_section::infos)]];
    [self updateInfoCell:cell atRow:row];
}

- (void)updateTableObjects {
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
        if (indexPath && [[self class] isObjectsSection:indexPath]) {
            auto const entity = [[self class] entityForSection:top_section(indexPath.section)];
            [self updateTableObjectCellAtIndex:indexPath.row entity:entity];
        }
    }
}

- (void)updateTableObjectCellAtIndex:(NSUInteger)index entity:(db_controller::entity const)entity {
    auto section = [[self class] sectionForEntity:entity];
    UITableViewCell *cell =
        [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:to_idx(section)]];
    auto const &object = _db_controller->object(entity, index);

    [self updateObjectCell:cell withObject:object];
}

- (void)updateTableForInsertedRow:(NSInteger)row entity:(db_controller::entity const)entity {
    auto const db_obj_count = _db_controller->object_count(entity);
    auto section = [[self class] sectionForEntity:entity];

    if (db_obj_count > 0 && db_obj_count - 1 == [self.tableView numberOfRowsInSection:to_idx(section)]) {
        auto indexPath = [NSIndexPath indexPathForRow:row inSection:to_idx(section)];
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self updateTableInfos];
        [self updateTableActions];
    } else {
        [self updateTable];
    }
}

- (void)updateTableForDeletedRow:(NSInteger)row entity:(db_controller::entity const)entity {
    auto indexPath = [NSIndexPath indexPathForRow:row inSection:to_idx([[self class] sectionForEntity:entity])];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updateTableInfos];
    [self updateTableActions];
}

- (void)showErrorAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nullptr]];

    [self presentViewController:alert animated:YES completion:nullptr];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _db_controller ? to_idx(top_section::last) + 1 : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (_db_controller) {
        switch (top_section(section)) {
            case top_section::actions:
                return to_idx(top_action_row::last) + 1;
            case top_section::infos:
                return to_idx(top_info_row::last) + 1;
            case top_section::objects_a:
                return _db_controller->object_count(db_controller::entity::a);
            case top_section::objects_b:
                return _db_controller->object_count(db_controller::entity::b);
        }
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (_db_controller) {
        switch (top_section(section)) {
            case top_section::actions:
                return @"Actions";
            case top_section::infos:
                return @"Info";
            case top_section::objects_a:
                return @"Objects A";
            case top_section::objects_b:
                return @"Objects B";
        }
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 30.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;

    switch (top_section(indexPath.section)) {
        case top_section::actions:
            cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
            [self updateActionCell:cell atRow:top_action_row(indexPath.row)];
            break;
        case top_section::infos:
            cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
            [self updateInfoCell:cell atRow:top_info_row(indexPath.row)];
            break;

        case top_section::objects_a: {
            if (indexPath.row < _db_controller->object_count(db_controller::entity::a)) {
                cell = [tableView dequeueReusableCellWithIdentifier:@"ObjectCell" forIndexPath:indexPath];
                auto const &object = _db_controller->object(db_controller::entity::a, size_t(indexPath.row));
                [self updateObjectCell:cell withObject:object];
            }
        } break;

        case top_section::objects_b: {
            if (indexPath.row < _db_controller->object_count(db_controller::entity::b)) {
                cell = [tableView dequeueReusableCellWithIdentifier:@"ObjectCell" forIndexPath:indexPath];
                auto const &object = _db_controller->object(db_controller::entity::b, size_t(indexPath.row));
                [self updateObjectCell:cell withObject:object];
            }
        } break;
    }

    return cell;
}

- (void)updateActionCell:(UITableViewCell *)cell atRow:(top_action_row)row {
    if (!cell) {
        return;
    }

    bool enabled = true;

    switch (row) {
        case top_action_row::create_a:
            cell.textLabel.text = @"Create A";
            break;
        case top_action_row::create_b:
            cell.textLabel.text = @"Create B";
            break;
        case top_action_row::insert_a:
            cell.textLabel.text = @"Insert A";
            enabled = _db_controller->can_insert();
            break;
        case top_action_row::insert_b:
            cell.textLabel.text = @"Insert B";
            enabled = _db_controller->can_insert();
            break;
        case top_action_row::undo:
            cell.textLabel.text = @"Undo";
            enabled = _db_controller->can_undo();
            break;
        case top_action_row::redo:
            cell.textLabel.text = @"Redo";
            enabled = _db_controller->can_redo();
            break;
        case top_action_row::clear:
            cell.textLabel.text = @"Clear";
            enabled = _db_controller->can_clear();
            break;
        case top_action_row::purge:
            cell.textLabel.text = @"Purge";
            enabled = _db_controller->can_purge();
            break;
        case top_action_row::save_changed:
            cell.textLabel.text = @"Save Changed";
            enabled = _db_controller->has_changed();
            break;
        case top_action_row::cancel_changed:
            cell.textLabel.text = @"Cancel Changed";
            enabled = _db_controller->has_changed();
            break;
    }

    if (enabled) {
        cell.textLabel.textColor = [UIColor blackColor];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    } else {
        cell.textLabel.textColor = [UIColor lightGrayColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
}

- (void)updateInfoCell:(UITableViewCell *)cell atRow:(top_info_row const &)row {
    if (!cell) {
        return;
    }

    switch (row) {
        case top_info_row::save_id: {
            cell.textLabel.text =
                [NSString stringWithFormat:@"current_save_id : %@ / last_save_id : %@",
                                           @(_db_controller->current_save_id()), @(_db_controller->last_save_id())];
        } break;
        case top_info_row::object_count: {
            auto a_count = _db_controller->object_count(db_controller::entity::a);
            auto b_count = _db_controller->object_count(db_controller::entity::b);
            cell.textLabel.text = [NSString stringWithFormat:@"object count A:%@ B:%@", @(a_count), @(b_count)];
        } break;
    }

    cell.textLabel.textColor = [UIColor blackColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}

- (void)updateObjectCell:(UITableViewCell *)cell withObject:(db::object const &)object {
    auto entity = db_controller::entity_for_name(object.entity_name());

    CFStringRef cf_id_str = to_cf_object(to_string(object.object_id()));
    CFStringRef cf_name_str = to_cf_object(to_string(object.attribute_value("name")));

    switch (entity) {
        case db_controller::entity::a: {
            CFStringRef cf_age_str = to_cf_object(to_string(object.attribute_value("age")));
            cell.textLabel.text =
                [NSString stringWithFormat:@"obj_id:%@ age:%@ name:%@", cf_id_str, cf_age_str, cf_name_str];
        } break;
        case db_controller::entity::b: {
            cell.textLabel.text = [NSString stringWithFormat:@"obj_id:%@ name:%@", cf_id_str, cf_name_str];
        } break;
    }

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == to_idx(top_section::actions)) {
        auto unowned_self = make_objc_ptr([[YASUnownedObject<DBSampleTopViewController *> alloc] initWithObject:self]);
        db::completion_f completion = [unowned_self](db::manager_result_t result) {
            if (!result) {
                auto controller = [unowned_self.object() object];
                CFStringRef cf_string = to_cf_object(to_string(result.error()));
                [controller showErrorAlertWithTitle:@"Setup Error" message:(__bridge NSString *)cf_string];
            }
        };

        switch (top_action_row(indexPath.row)) {
            case top_action_row::create_a:
                _db_controller->create_object(db_controller::entity::a);
                break;
            case top_action_row::create_b:
                _db_controller->create_object(db_controller::entity::b);
                break;
            case top_action_row::insert_a:
                _db_controller->insert(db_controller::entity::a, std::move(completion));
                break;
            case top_action_row::insert_b:
                _db_controller->insert(db_controller::entity::b, std::move(completion));
                break;
            case top_action_row::undo:
                _db_controller->undo(std::move(completion));
                break;
            case top_action_row::redo:
                _db_controller->redo(std::move(completion));
                break;
            case top_action_row::clear:
                _db_controller->clear(std::move(completion));
                break;
            case top_action_row::purge:
                _db_controller->purge(std::move(completion));
                break;
            case top_action_row::save_changed:
                _db_controller->save_changed(std::move(completion));
                break;
            case top_action_row::cancel_changed:
                _db_controller->cancel_changed(std::move(completion));
                break;
        }
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([[self class] isObjectsSection:indexPath]) {
        return YES;
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        if ([[self class] isObjectsSection:indexPath]) {
            auto const entity = [[self class] entityForSection:top_section(indexPath.section)];
            _db_controller->remove(entity, static_cast<std::size_t>(indexPath.row));
        }
    }
}

+ (BOOL)isObjectsSection:(NSIndexPath *)indexPath {
    return (indexPath.section == to_idx(top_section::objects_a) || indexPath.section == to_idx(top_section::objects_b));
}

+ (top_section)sectionForEntity:(db_controller::entity const)entity {
    switch (entity) {
        case db_controller::entity::a:
            return top_section::objects_a;
        case db_controller::entity::b:
            return top_section::objects_b;
    }
}

+ (db_controller::entity)entityForSection:(top_section const &)section {
    switch (section) {
        case top_section::objects_a:
            return db_controller::entity::a;
        case top_section::objects_b:
            return db_controller::entity::b;
        default:
            throw std::invalid_argument("invalid section.");
    }
}

@end
