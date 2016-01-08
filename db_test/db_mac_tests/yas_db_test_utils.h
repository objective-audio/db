//
//  yas_db_test_utils.h
//

#import <XCTest/XCTest.h>
#import "yas_cf_utils.h"
#import "yas_db.h"

@interface yas_db_test_utils : NSObject

+ (yas::db::database)create_test_database;
+ (yas::db::manager)create_test_manager;
+ (std::string)database_path;
+ (NSString *)databasePath;
+ (void)deleteDatabase;

+ (NSDictionary *)model_dictionary_0_0_1;
+ (NSDictionary *)model_dictionary_0_0_2;

@end
