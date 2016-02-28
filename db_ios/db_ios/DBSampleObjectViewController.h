//
//  DBSampleObjectViewController.h
//

#import <UIKit/UIKit.h>
#import "yas_db.h"
#import "yas_db_sample_controller.h"

@interface DBSampleObjectViewController : UIViewController

- (void)setDbController:(std::shared_ptr<yas::sample::db_controller>)controller dbObject:(yas::db::object)object;

@end
