//
//  DBSampleObjectSelectionViewController.mm
//

#import "DBSampleObjectSelectionViewController.h"
#import "DBSampleObjectNormalCell.h"
#import "yas_objc_cast.h"
#import "yas_cf_utils.h"

using namespace yas;
using namespace yas::sample;

namespace yas::sample {
static NSString *const selection_normal_cell_id = @"NormalCell";
}

@implementation DBSampleObjectSelectionViewController {
    std::weak_ptr<db_controller> _db_controller;
    db_controller::entity _entity;
    std::function<void(db::object const &)> _selected_handler;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = (__bridge NSString *)to_cf_object(to_entity_name(_entity));
}

- (void)set_db_controller:(std::weak_ptr<yas::sample::db_controller>)controller
                   entity:(db_controller::entity const)entity
         selected_handler:(std::function<void(db::object const &)>)handler {
    _db_controller = std::move(controller);
    _entity = entity;
    _selected_handler = std::move(handler);
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (auto db_controller = _db_controller.lock()) {
        return db_controller->object_count(_entity);
    } else {
        return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:selection_normal_cell_id forIndexPath:indexPath];

    if (auto normalCell = objc_cast<DBSampleObjectNormalCell>(cell)) {
        auto const &object = _db_controller.lock()->object(_entity, indexPath.row);
        auto const &name = object.attribute_value("name");
        [normalCell setupWithTitle:"object_id:" + to_string(object.object_id()) + " name:" + to_string(name)];
        normalCell.selectionStyle = UITableViewCellSelectionStyleDefault;
        normalCell.textLabel.textColor = [UIColor blackColor];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self.navigationController.visibleViewController isEqual:self]) {
        return;
    }

    if (!_selected_handler) {
        return;
    }

    if (auto db_controller = _db_controller.lock()) {
        auto const &object = db_controller->object(_entity, indexPath.row);
        _selected_handler(object);

        [self.navigationController popViewControllerAnimated:YES];

        _selected_handler = nullptr;
    }
}

@end
