//
//  DBSampleObjectViewController.h
//

#import <UIKit/UIKit.h>
#import "yas_sample_db_controller.h"

@interface DBSampleObjectViewController : UITableViewController

- (void)set_db_controller:(std::weak_ptr<yas::sample::db_controller>)controller db_object:(yas::db::object_ptr const &)object;

@end
