//
//  DBSampleObjectTextFieldCell.m
//

#import "DBSampleObjectTextFieldCell.h"
#import <cpp_utils/yas_cf_utils.h>

using namespace yas;

@interface DBSampleObjectTextFieldCell ()

@property (nonatomic, weak) IBOutlet UILabel *label;
@property (nonatomic, weak) IBOutlet UITextField *textField;

@end

@implementation DBSampleObjectTextFieldCell {
    std::function<void(std::string const &)> _handler;
}

- (void)prepareForReuse {
    [super prepareForReuse];

    self.label.text = nil;
    self.textField.text = nil;
    _handler = nullptr;
}

- (void)setupWithTitle:(std::string const &)title
                  text:(std::string const &)text
               handler:(std::function<void(std::string const &)>)handler {
    self.label.text = (__bridge NSString *)to_cf_object(title);
    self.textField.text = (__bridge NSString *)to_cf_object(text);
    _handler = handler;
}

- (IBAction)testFieldEditingChanged:(UITextField *)textField {
    if (_handler) {
        CFStringRef cf_str = (__bridge CFStringRef)textField.text;
        auto const str = to_string(cf_str);
        _handler(str);
    }
}

@end
