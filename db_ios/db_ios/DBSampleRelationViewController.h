//
//  DBSampleRelationViewController.h
//

#import <UIKit/UIKit.h>
#import "yas_sample_db_controller.h"

@interface DBSampleRelationViewController : UITableViewController

- (void)set_db_controller:(std::weak_ptr<yas::sample::db_controller>)controller
                   object:(yas::db::object)object
             relationName:(std::string)rel_name;

@end
