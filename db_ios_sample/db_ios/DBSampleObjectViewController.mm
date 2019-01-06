//
//  DBSampleObjectViewController.mm
//

#import "DBSampleObjectViewController.h"
#import "DBSampleObjectNormalCell.h"
#import "DBSampleObjectTextFieldCell.h"
#import "DBSampleRelationViewController.h"
#import "yas_cf_utils.h"
#import "yas_objc_cast.h"
#import "yas_objc_ptr.h"
#import "yas_objc_unowned.h"
#import "yas_to_integer.h"

using namespace yas;
using namespace yas::sample;

namespace yas::sample {
enum class object_section : std::size_t {
    info,
    attributes,
    relations,

    last = relations,
};

enum class object_info_row : std::size_t {
    object_id,

    last = object_id,
};

using object_section_type_t = std::underlying_type_t<object_section>;
using object_info_row_type_t = std::underlying_type_t<object_info_row>;

static NSString *const object_normal_cell_id = @"NormalCell";
static NSString *const object_text_field_cell_id = @"TextFieldCell";
static NSString *const object_relation_cell_id = @"RelationCell";
}

namespace yas {
sample::object_section_type_t to_idx(object_section const &section) {
    return object_section_type_t(section);
}

sample::object_info_row_type_t to_idx(object_info_row const &row) {
    return object_info_row_type_t(row);
}
}

@implementation DBSampleObjectViewController {
    std::weak_ptr<yas::sample::db_controller> _db_controller;
    std::experimental::optional<db::object> _db_object;
    std::vector<db::attribute> _attributes;
    std::vector<db::relation> _relations;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = (__bridge NSString *)to_cf_object(to_string([self db_object].object_id()));
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if (auto const viewController = objc_cast<DBSampleRelationViewController>(segue.destinationViewController)) {
        if (auto const cell = objc_cast<UITableViewCell>(sender)) {
            auto const indexPath = [self.tableView indexPathForCell:cell];
            [viewController set_db_controller:_db_controller
                                       object:[self db_object]
                                 relationName:_relations.at(indexPath.row).name];
        } else {
            throw std::runtime_error("invalid sender class.");
        }
    }
}

- (void)set_db_controller:(std::weak_ptr<yas::sample::db_controller>)controller db_object:(yas::db::object)object {
    _db_controller = std::move(controller);
    *_db_object = object;

    _attributes.clear();
    _relations.clear();

    if (object) {
        _attributes =
            to_vector<db::attribute>(object.entity().custom_attributes, [](auto const &pair) { return pair.second; });
        _relations = to_vector<db::relation>(object.entity().relations, [](auto const &pair) { return pair.second; });
    }
}

- (db::object &)db_object {
    return *_db_object;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return to_idx(object_section::last) + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (object_section(section)) {
        case object_section::info:
            return to_idx(object_info_row::last) + 1;

        case object_section::attributes:
            return _attributes.size();

        case object_section::relations:
            return _relations.size();
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (object_section(section)) {
        case object_section::attributes:
            return @"Attributes";

        case object_section::relations:
            return @"Relations";

        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    auto unowned = make_objc_ptr([[YASUnownedObject<DBSampleObjectViewController *> alloc] initWithObject:self]);

    switch (object_section(indexPath.section)) {
        case object_section::info: {
            switch (object_info_row(indexPath.row)) {
                case object_info_row::object_id:
                    cell = [tableView dequeueReusableCellWithIdentifier:sample::object_normal_cell_id
                                                           forIndexPath:indexPath];
                    if (auto normalCell = objc_cast<DBSampleObjectNormalCell>(cell)) {
                        auto title = "object_id : " + to_string(self.db_object.object_id());
                        [normalCell setupWithTitle:title];
                    }
                    break;
            }
        } break;

        case object_section::attributes: {
            cell =
                [tableView dequeueReusableCellWithIdentifier:sample::object_text_field_cell_id forIndexPath:indexPath];
            if (auto textFieldCell = objc_cast<DBSampleObjectTextFieldCell>(cell)) {
                if (indexPath.row < _attributes.size()) {
                    auto const &attribute = _attributes.at(indexPath.row);
                    auto const &attr_name = attribute.name;
                    if (attribute.type == db::integer::name) {
                        [textFieldCell setupWithTitle:attr_name
                                                 text:to_string(self.db_object.attribute_value(attr_name))
                                              handler:[unowned, attr_name](std::string const &text) {
                                                  auto &obj = [unowned.object().object db_object];
                                                  obj.set_attribute_value(
                                                      attr_name, db::value{to_integer<db::integer::type>(text)});
                                              }];
                    } else if (attribute.type == db::text::name) {
                        [textFieldCell setupWithTitle:attr_name
                                                 text:to_string(self.db_object.attribute_value(attr_name))
                                              handler:[unowned, attr_name](std::string const &text) {
                                                  auto &obj = [unowned.object().object db_object];
                                                  obj.set_attribute_value(attr_name, db::value{text});
                                              }];
                    }
                }
            }
        } break;

        case object_section::relations: {
            cell = [tableView dequeueReusableCellWithIdentifier:sample::object_relation_cell_id forIndexPath:indexPath];
            if (auto normalCell = objc_cast<DBSampleObjectNormalCell>(cell)) {
                auto title = "relation : " + _relations.at(indexPath.row).name;
                [normalCell setupWithTitle:title];
            }
        } break;
    }

    return cell;
}

@end
