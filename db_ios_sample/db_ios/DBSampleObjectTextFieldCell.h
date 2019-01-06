//
//  DBSampleObjectTextFieldCell.h
//

#import <UIKit/UIKit.h>
#import <functional>
#import <string>

@interface DBSampleObjectTextFieldCell : UITableViewCell

- (void)setupWithTitle:(std::string const &)title
                  text:(std::string const &)text
               handler:(std::function<void(std::string const &)>)handler;

@end
