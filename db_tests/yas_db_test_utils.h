//
//  yas_db_test_utils.h
//

#import <XCTest/XCTest.h>
#import <cpp_utils/yas_cf_utils.h>
#import <cpp_utils/yas_task.h>
#import <cpp_utils/yas_version.h>
#import <db/db.h>

@interface yas_db_test_utils : NSObject

+ (yas::db::database_ptr)create_test_database;
+ (yas::db::manager_ptr)create_test_manager;
+ (yas::db::manager_ptr)create_test_manager:(yas::db::model const &)model;
+ (yas::db::manager_ptr)create_test_manager:(yas::db::model const &)model priority_count:(size_t)count;
+ (yas::db::manager_ptr)create_test_manager:(yas::db::model const &)model
                         priority_count:(size_t)count
                         dispatch_queue:(dispatch_queue_t)queue;
+ (std::string)database_path;
+ (NSString *)databasePath;
+ (void)deleteDatabase;

+ (yas::db::model)model_0_0_0;
+ (yas::db::model)model_0_0_1;
+ (yas::db::model)model_0_0_2;

@end
