//
//  yas_db_test_utils.h
//

#import <XCTest/XCTest.h>
#import <cpp_utils/yas_cf_utils.h>
#import <cpp_utils/yas_task.h>
#import <cpp_utils/yas_version.h>
#import <db/yas_db_umbrella.h>

@interface yas_db_test_utils : NSObject

+ (yas::db::database_ptr)create_test_database;
+ (yas::db::manager)create_test_manager;
+ (yas::db::manager)create_test_manager:(yas::db::model &&)model;
+ (yas::db::manager)create_test_manager:(yas::db::model &&)model priority_count:(size_t)count;
+ (yas::db::manager)create_test_manager:(yas::db::model &&)model
                         priority_count:(size_t)count
                         dispatch_queue:(dispatch_queue_t)queue;
+ (std::string)database_path;
+ (NSString *)databasePath;
+ (void)deleteDatabase;

+ (yas::db::model)model_0_0_1;
+ (yas::db::model)model_0_0_2;

@end
