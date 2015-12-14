//
//  yas_db_test_utils.h
//

#import <XCTest/XCTest.h>
#import "yas_cf_utils.h"
#import "yas_db.h"

@interface yas_db_test_utils : NSObject

+ (yas::db::database)create_test_database;
+ (NSString *)databasePath;
+ (void)deleteDatabase;

@end
