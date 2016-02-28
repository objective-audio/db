//
//  DBSampleObjectViewController.mm
//

#import "DBSampleObjectViewController.h"
#import "yas_cf_utils.h"

namespace yas {
namespace sample {
    struct object_holder {
        db::object object = nullptr;
    };
}
}

using namespace yas;
using namespace yas::sample;

@interface DBSampleObjectViewController () <UITextFieldDelegate>

@property (nonatomic, weak) IBOutlet UILabel *idLabel;
@property (nonatomic, weak) IBOutlet UITextField *nameTextField;
@property (nonatomic, weak) IBOutlet UITextField *ageTextField;

@end

@implementation DBSampleObjectViewController {
    std::shared_ptr<db_controller> _controller;
    object_holder _holder;
    bool changed;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    CFStringRef cf_id_str = to_cf_object(to_string(_holder.object.get_attribute(db::object_id_field)));
    self.idLabel.text = [NSString stringWithFormat:@"object_id : %@", cf_id_str];

    CFStringRef cf_name_str = to_cf_object(to_string(_holder.object.get_attribute("name")));
    self.nameTextField.text = (__bridge NSString *)cf_name_str;

    auto age = _holder.object.get_attribute("age").get<db::integer>();
    self.ageTextField.text = @(age).stringValue;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (changed) {
        _controller->send_object_did_change();
    }
}

- (void)setDbController:(std::shared_ptr<yas::sample::db_controller>)controller dbObject:(yas::db::object)object {
    _controller = controller;
    _holder.object = object;
}

#pragma mark -

- (IBAction)testFieldEditingChanged:(UITextField *)textField {
    if ([textField isEqual:self.nameTextField]) {
        CFStringRef cf_str = (__bridge CFStringRef)textField.text;
        _holder.object.set_attribute("name", db::value{to_string(cf_str)});
    } else if ([textField isEqual:self.ageTextField]) {
        auto value = db::value{db::integer::type{[textField.text integerValue]}};
        _holder.object.set_attribute("age", value);
    }

    changed = true;
}

@end
