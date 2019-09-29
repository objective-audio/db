//
//  DBSampleObjectSelectionViewController.h
//

#import <UIKit/UIKit.h>
#import "yas_sample_db_controller.h"

@interface DBSampleObjectSelectionViewController : UITableViewController

- (void)set_db_controller:(std::weak_ptr<yas::sample::db_controller>)controller
                   entity:(yas::sample::db_controller::entity const)entity
         selected_handler:(std::function<void(yas::db::object_ptr const &)>)handler;

@end
