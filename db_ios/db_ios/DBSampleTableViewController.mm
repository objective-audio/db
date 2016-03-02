//
//  DBSampleTableViewController.mm
//

#import "DBSampleObjectViewController.h"
#import "DBSampleTableViewController.h"
#import "yas_cf_utils.h"
#import "yas_db.h"
#import "yas_db_sample_controller.h"
#import "yas_objc_container.h"

using namespace yas;
using namespace yas::sample;

typedef NS_ENUM(NSUInteger, DBSampleSection) {
    DBSampleSectionActions,
    DBSampleSectionInfos,
    DBSampleSectionObjects,

    DBSampleSectionCount,
};

typedef NS_ENUM(NSUInteger, DBSampleActionRow) {
    DBSampleActionRowAdd,
    DBSampleActionRowUndo,
    DBSampleActionRowRedo,
    DBSampleActionRowClear,
    DBSampleActionRowPurge,
    DBSampleActionRowSaveChanged,
    DBSampleActionRowCancelChanged,

    DBSampleActionRowCount,
};

typedef NS_ENUM(NSUInteger, DBSampleInfoRow) {
    DBSampleInfoRowSaveID,
    DBSampleInfoRowObjectCount,

    DBSampleInfoRowCount,
};

@interface DBSampleTableViewController ()

@end

@implementation DBSampleTableViewController {
    std::shared_ptr<db_controller> _db_controller;
    std::vector<yas::observer<db::value>> _observers;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.rightBarButtonItem = self.editButtonItem;

    _db_controller = std::make_shared<db_controller>();

    yas::objc::container<objc::weak> weak_container{self};

    auto proccessing_observer = _db_controller->subject().make_observer(
        db_controller::processing_did_change_key, [weak_container](auto const &key, db::value const &value) {
            if (auto self_container = weak_container.lock()) {
                DBSampleTableViewController *controller = self_container.object();
                if (value.get<db::integer>()) {
                    controller.title = @"Processing...";
                } else {
                    controller.title = nil;
                }
            }
        });

    _observers.emplace_back(std::move(proccessing_observer));

    _db_controller->setup([weak_container](auto result) {
        if (auto self_container = weak_container.lock()) {
            DBSampleTableViewController *controller = self_container.object();

            if (result) {
                [controller setupObserversAfterSetup];
                [controller updateTable];
            } else {
                CFStringRef cf_string = to_cf_object(to_string(result.error().type()));
                [controller showErrorAlertWithTitle:@"Setup Error" message:(__bridge NSString *)cf_string];
            }
        }
    });
}

- (void)setupObserversAfterSetup {
    yas::objc::container<objc::weak> weak_container{self};

    auto observer =
        _db_controller->subject().make_wild_card_observer([weak_container](auto const &key, db::value const &value) {
            if (auto self_container = weak_container.lock()) {
                DBSampleTableViewController *controller = self_container.object();

                if (key == db_controller::db_info_did_change_key) {
                    [controller updateTableForInfo:DBSampleInfoRowSaveID];
                } else if (key == db_controller::objects_did_update_key) {
                    [controller updateTable];
                } else if (key == db_controller::object_did_insert_key) {
                    [controller updateTableForInsertedRow:NSInteger(value.get<db::integer>())];
                } else if (key == db_controller::object_did_remove_key) {
                    [controller updateTableForDeletedRow:NSInteger(value.get<db::integer>())];
                } else if (key == db_controller::object_did_change_key) {
                    if (value) {
                        [controller updateTableObjectCellAtIndex:NSInteger(value.get<db::integer>())];
                    } else {
                        [controller updateTableObjects];
                    }
                    [controller updateTableActions];
                }
            }
        });

    _observers.emplace_back(std::move(observer));
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.destinationViewController isKindOfClass:[DBSampleObjectViewController class]]) {
        DBSampleObjectViewController *controller = segue.destinationViewController;

        NSIndexPath *indexPath = [self.tableView indexPathForCell:sender];
        if (indexPath.row != NSNotFound) {
            [controller setDbController:_db_controller
                               dbObject:_db_controller->object(static_cast<std::size_t>(indexPath.row))];
        }
    }
}

- (void)updateTable {
    [self updateTableActions];
    [self updateTableInfos];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:DBSampleSectionObjects]
                  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)updateTableActions {
    for (auto &idx : each_index<std::size_t>{DBSampleActionRowCount}) {
        [self updateTableForAction:DBSampleActionRow(idx)];
    }
}

- (void)updateTableForAction:(DBSampleActionRow)row {
    UITableViewCell *cell =
        [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:DBSampleSectionActions]];
    [self updateActionCell:cell atRow:row];
}

- (void)updateTableInfos {
    [self updateTableForInfo:DBSampleInfoRowSaveID];
    [self updateTableForInfo:DBSampleInfoRowObjectCount];
}

- (void)updateTableForInfo:(DBSampleInfoRow)row {
    UITableViewCell *cell =
        [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:DBSampleSectionInfos]];
    [self updateInfoCell:cell atRow:row];
}

- (void)updateTableObjects {
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
        if (indexPath) {
            [self updateTableObjectCellAtIndex:indexPath.row];
        }
    }
}

- (void)updateTableObjectCellAtIndex:(NSUInteger)index {
    UITableViewCell *cell =
        [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:DBSampleSectionObjects]];
    auto const &object = _db_controller->object(index);

    [self updateObjectCell:cell withObject:object];
}

- (void)updateTableForInsertedRow:(NSInteger)row {
    auto const db_obj_count = _db_controller->object_count();
    if (db_obj_count > 0 && db_obj_count - 1 == [self.tableView numberOfRowsInSection:DBSampleSectionObjects]) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:DBSampleSectionObjects];
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self updateTableInfos];
        [self updateTableActions];
    } else {
        [self updateTable];
    }
}

- (void)updateTableForDeletedRow:(NSInteger)row {
    if (_db_controller->object_count() + 1 == [self.tableView numberOfRowsInSection:DBSampleSectionObjects]) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:DBSampleSectionObjects];
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self updateTableInfos];
        [self updateTableActions];
    } else {
        [self updateTable];
    }
}

- (void)showErrorAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nullptr]];

    [self presentViewController:alert animated:YES completion:nullptr];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _db_controller ? DBSampleSectionCount : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (_db_controller) {
        switch (section) {
            case DBSampleSectionActions:
                return DBSampleActionRowCount;
            case DBSampleSectionInfos:
                return DBSampleInfoRowCount;
            case DBSampleSectionObjects:
                return _db_controller->object_count();
        }
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (_db_controller) {
        switch (section) {
            case DBSampleSectionActions:
                return @"Actions";
            case DBSampleSectionInfos:
                return @"Info";
            case DBSampleSectionObjects:
                return @"Objects";
        }
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 30.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;

    if (indexPath.section == DBSampleSectionObjects) {
        if (indexPath.row < _db_controller->object_count()) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"ObjectCell" forIndexPath:indexPath];
            auto const &object = _db_controller->object(size_t(indexPath.row));
            [self updateObjectCell:cell withObject:object];
        }
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];

        switch (indexPath.section) {
            case DBSampleSectionActions:
                [self updateActionCell:cell atRow:DBSampleActionRow(indexPath.row)];
                break;
            case DBSampleSectionInfos:
                [self updateInfoCell:cell atRow:DBSampleInfoRow(indexPath.row)];
                break;
        }
    }

    return cell;
}

- (void)updateActionCell:(UITableViewCell *)cell atRow:(DBSampleActionRow)row {
    if (!cell) {
        return;
    }

    bool enabled = true;

    switch (row) {
        case DBSampleActionRowAdd:
            cell.textLabel.text = @"Add";
            break;
        case DBSampleActionRowUndo:
            cell.textLabel.text = @"Undo";
            enabled = _db_controller->can_undo();
            break;
        case DBSampleActionRowRedo:
            cell.textLabel.text = @"Redo";
            enabled = _db_controller->can_redo();
            break;
        case DBSampleActionRowClear:
            cell.textLabel.text = @"Clear";
            enabled = _db_controller->can_clear();
            break;
        case DBSampleActionRowPurge:
            cell.textLabel.text = @"Purge";
            enabled = _db_controller->can_purge();
            break;
        case DBSampleActionRowSaveChanged:
            cell.textLabel.text = @"Save Changed";
            enabled = _db_controller->has_changed();
            break;
        case DBSampleActionRowCancelChanged:
            cell.textLabel.text = @"Cancel Changed";
            enabled = _db_controller->has_changed();
            break;
        default:
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

- (void)updateInfoCell:(UITableViewCell *)cell atRow:(DBSampleInfoRow)row {
    if (!cell) {
        return;
    }

    switch (row) {
        case DBSampleInfoRowSaveID:
            cell.textLabel.text =
                [NSString stringWithFormat:@"current_save_id : %@ / last_save_id : %@",
                                           @(_db_controller->current_save_id()), @(_db_controller->last_save_id())];
            break;
        case DBSampleInfoRowObjectCount:
            cell.textLabel.text = [NSString stringWithFormat:@"object count : %@", @(_db_controller->object_count())];
            break;
        default:
            break;
    }

    cell.textLabel.textColor = [UIColor blackColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}

- (void)updateObjectCell:(UITableViewCell *)cell withObject:(db::object const &)object {
    CFStringRef cf_id_str = to_cf_object(to_string(object.get_attribute(db::object_id_field)));
    CFStringRef cf_age_str = to_cf_object(to_string(object.get_attribute("age")));
    CFStringRef cf_name_str = to_cf_object(to_string(object.get_attribute("name")));
    cell.textLabel.text = [NSString stringWithFormat:@"obj_id:%@ age:%@ name:%@", cf_id_str, cf_age_str, cf_name_str];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == DBSampleSectionActions) {
        switch (indexPath.row) {
            case DBSampleActionRowAdd:
                _db_controller->add();
                break;
            case DBSampleActionRowUndo:
                _db_controller->undo();
                break;
            case DBSampleActionRowRedo:
                _db_controller->redo();
                break;
            case DBSampleActionRowClear:
                _db_controller->clear();
                break;
            case DBSampleActionRowPurge:
                _db_controller->purge();
                break;
            case DBSampleActionRowSaveChanged:
                _db_controller->save();
                break;
            case DBSampleActionRowCancelChanged:
                _db_controller->cancel();
                break;
        }
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == DBSampleSectionObjects) {
        return YES;
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        if (indexPath.section == DBSampleSectionObjects) {
            _db_controller->remove(static_cast<std::size_t>(indexPath.row));
        }
    }
}

@end
