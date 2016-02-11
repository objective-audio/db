//
//  yas_db_test_utils.m
//

#import "yas_db_test_utils.h"

using namespace yas;

@implementation yas_db_test_utils

+ (db::database)create_test_database {
    NSString *databasePath = [[self class] databasePath];
    std::string db_path = yas::to_string((__bridge CFStringRef)databasePath);
    return db::database{db_path};
}

+ (db::manager)create_test_manager {
    return [self create_test_manager:db::model{nullptr}];
}

+ (db::manager)create_test_manager:(db::model &&)model {
    return [self create_test_manager:std::move(model) priority_count:1];
}

+ (yas::db::manager)create_test_manager:(yas::db::model &&)model priority_count:(size_t)count {
    NSString *databasePath = [[self class] databasePath];
    std::string db_path = yas::to_string((__bridge CFStringRef)databasePath);
    return db::manager{db_path, std::move(model), count};
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
        },
        @"indices": @{
            @"sample_a_name": @{@"entity": @"sample_a", @"attributes": @[@"name"]},
            @"sample_a_others": @{@"entity": @"sample_a", @"attributes": @[@"age", @"weight"]}
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
            @"sample_b": @{
                @"attributes": @{@"name": @{@"type": @"text"}},
                @"relations": @{@"parent": @{@"target": @"sample_a"}}
            },
            @"sample_c": @{
                @"attributes": @{@"name": @{@"type": @"text"}},
                @"relations": @{@"friend": @{@"target": @"sample_a"}}
            }
        },
        @"indices": @{
            @"sample_a_name": @{@"entity": @"sample_a", @"attributes": @[@"name"]},
            @"sample_a_others": @{@"entity": @"sample_a", @"attributes": @[@"age", @"weight"]},
            @"sample_b_name": @{@"entity": @"sample_b", @"attributes": @[@"name"]}
        }
    };
}

@end
