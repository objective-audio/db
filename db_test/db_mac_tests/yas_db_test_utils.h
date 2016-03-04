//
//  yas_db_test_utils.h
//

#import <XCTest/XCTest.h>
#import "yas_cf_utils.h"
#import "yas_db.h"
#import "yas_operation.h"
#import "yas_version.h"

@interface yas_db_test_utils : NSObject

+ (yas::db::database)create_test_database;
+ (yas::db::manager)create_test_manager;
+ (yas::db::manager)create_test_manager:(yas::db::model &&)model;
+ (yas::db::manager)create_test_manager:(yas::db::model &&)model priority_count:(size_t)count;
+ (yas::db::manager)create_test_manager:(yas::db::model &&)model
                         priority_count:(size_t)count
                         dispatch_queue:(dispatch_queue_t)queue;
+ (std::string)database_path;
+ (NSString *)databasePath;
+ (void)deleteDatabase;

+ (NSDictionary *)model_dictionary_0_0_1;
+ (NSDictionary *)model_dictionary_0_0_2;

@end
