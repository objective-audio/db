//
//  yas_db_test_utils.m
//

#import "yas_db_test_utils.h"

@implementation yas_db_test_utils

+ (yas::db::database)create_test_database {
    NSString *databasePath = [[self class] databasePath];
    std::string db_path = yas::to_string((__bridge CFStringRef)databasePath);
    return yas::db::database{db_path};
}

+ (yas::db::manager)create_test_manager {
    NSString *databasePath = [[self class] databasePath];
    std::string db_path = yas::to_string((__bridge CFStringRef)databasePath);
    return yas::db::manager{db_path};
}

+ (std::string)database_path {
    return yas::to_string((__bridge CFStringRef)[self databasePath]);
}

+ (NSString *)databasePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = [paths objectAtIndex:0];
    return [dir stringByAppendingPathComponent:@"db_test.db"];
}

+ (void)deleteDatabase {
    NSString *path = [self databasePath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:path]) {
        [fileManager removeItemAtPath:path error:nil];
    }
}

+ (NSDictionary *)model_dictionary_0_0_1 {
    return @{
        @"version": @"0.0.1",
        @"entities": @{
            @"sample_a": @{
                @"attributes": @{
                    @"age": @{@"type": @"integer", @"default": @10, @"not_null": @YES},
                    @"name": @{@"type": @"text", @"default": @"default_value"},
                    @"weight": @{@"type": @"real", @"default": @65.4},
                    @"data": @{@"type": @"blob"}
                },
                @"relations": @{@"child": @{@"target": @"sample_b"}}
            },
            @"sample_b": @{@"attributes": @{@"name": @{@"type": @"text"}}, @"relations": @{}}
        }
    };
}

+ (NSDictionary *)model_dictionary_0_0_2 {
    return @{
        @"version": @"0.0.2",
        @"entities": @{
            @"sample_a": @{
                @"attributes": @{
                    @"age": @{@"type": @"integer", @"default": @10, @"not_null": @YES},
                    @"name": @{@"type": @"text", @"default": @"default_value"},
                    @"weight": @{@"type": @"real", @"default": @65.4},
                    @"tall": @{@"type": @"real", @"default": @172.4},
                    @"data": @{@"type": @"blob"}
                },
                @"relations": @{@"child": @{@"target": @"sample_b"}, @"friend": @{@"target": @"sample_c"}}
            },
            @"sample_b": @{@"attributes": @{@"name": @{@"type": @"text"}}, @"relations": @{}},
            @"sample_c": @{@"attributes": @{@"name": @{@"type": @"text"}}, @"relations": @{}}
        }
    };
}

@end
