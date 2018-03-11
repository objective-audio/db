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
    return [self create_test_manager:std::move(model) priority_count:count dispatch_queue:dispatch_get_main_queue()];
}

+ (yas::db::manager)create_test_manager:(yas::db::model &&)model
                         priority_count:(size_t)count
                         dispatch_queue:(dispatch_queue_t)queue {
    NSString *databasePath = [[self class] databasePath];
    std::string db_path = yas::to_string((__bridge CFStringRef)databasePath);
    return db::manager{db_path, std::move(model), count, queue};
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

+ (db::model)model_0_0_1 {
    yas::version version{"0.0.1"};

    db::entity_args sample_a{
        .name = "sample_a",
        .attributes = {{.name = "age",
                        .type = db::attribute_type::integer,
                        .default_value = db::value{db::integer::type{10}},
                        .not_null = true},
                       {.name = "name", .type = db::attribute_type::text, .default_value = db::value{"default_value"}},
                       {.name = "weight",
                        .type = db::attribute_type::real,
                        .default_value = db::value{db::real::type{65.4}}},
                       {.name = "data", .type = db::attribute_type::blob}},
        .relations = {{.name = "child", .target_entity_name = "sample_b"}}};

    db::entity_args sample_b{.name = "sample_b", .attributes = {{.name = "name", .type = db::attribute_type::text}}};

    db::entity_args_vector_t entities{std::move(sample_a), std::move(sample_b)};

    db::index_args sample_a_name_index{.name = "sample_a_name", .table_name = "sample_a", .attribute_names = {"name"}};
    db::index_args sample_a_others_index{
        .name = "sample_a_others", .table_name = "sample_a", .attribute_names = {"age", "weight"}};

    db::index_args_vector_t indices{std::move(sample_a_name_index), std::move(sample_a_others_index)};

    return db::model{
        db::model_args{.version = std::move(version), .entities = std::move(entities), .indices = std::move(indices)}};
}

+ (NSDictionary *)model_dictionary_0_0_1 {
    return @{
        @"version": @"0.0.1",
        @"entities": @{
            @"sample_a": @{
                @"attributes": @{
                    @"age": @{@"type": @"INTEGER", @"default": @10, @"not_null": @YES},
                    @"name": @{@"type": @"TEXT", @"default": @"default_value"},
                    @"weight": @{@"type": @"REAL", @"default": @65.4},
                    @"data": @{@"type": @"BLOB"}
                },
                @"relations": @{@"child": @{@"target": @"sample_b"}}
            },
            @"sample_b": @{@"attributes": @{@"name": @{@"type": @"TEXT"}}, @"relations": @{}}
        },
        @"indices": @{
            @"sample_a_name": @{@"entity": @"sample_a", @"attributes": @[@"name"]},
            @"sample_a_others": @{@"entity": @"sample_a", @"attributes": @[@"age", @"weight"]}
        }
    };
}

+ (db::model)model_0_0_2 {
    yas::version version{"0.0.2"};

    db::entity_args sample_a{
        .name = "sample_a",
        .attributes =
            {{.name = "age",
              .type = db::attribute_type::integer,
              .default_value = db::value{db::integer::type{10}},
              .not_null = true},
             {.name = "name", .type = db::attribute_type::text, .default_value = db::value{"default_value"}},
             {.name = "weight", .type = db::attribute_type::real, .default_value = db::value{db::real::type{65.4}}},
             {.name = "tall", .type = db::attribute_type::real, .default_value = db::value{db::real::type{172.4}}},
             {.name = "data", .type = db::attribute_type::blob}},
        .relations = {{.name = "child", .target_entity_name = "sample_b"},
                      {.name = "friend", .target_entity_name = "sample_c"}}};

    db::entity_args sample_b{.name = "sample_b",
                             .attributes = {{.name = "name", .type = db::attribute_type::text}},
                             .relations = {{.name = "parent", .target_entity_name = "sample_a"}}};

    db::entity_args sample_c{.name = "sample_c",
                             .attributes = {{.name = "name", .type = db::attribute_type::text}},
                             .relations = {{.name = "parent", .target_entity_name = "sample_a"}}};

    db::entity_args_vector_t entities{std::move(sample_a), std::move(sample_b), std::move(sample_c)};

    db::index_args sample_a_name_index{.name = "sample_a_name", .table_name = "sample_a", .attribute_names = {"name"}};
    db::index_args sample_a_others_index{
        .name = "sample_a_others", .table_name = "sample_a", .attribute_names = {"age", "weight"}};
    db::index_args sample_b_name_index{.name = "sample_b_name", .table_name = "sample_b", .attribute_names = {"name"}};

    db::index_args_vector_t indices{std::move(sample_a_name_index), std::move(sample_a_others_index),
                                    std::move(sample_b_name_index)};

    return db::model{
        db::model_args{.version = std::move(version), .entities = std::move(entities), .indices = std::move(indices)}};
}

+ (NSDictionary *)model_dictionary_0_0_2 {
    return @{
        @"version": @"0.0.2",
        @"entities": @{
            @"sample_a": @{
                @"attributes": @{
                    @"age": @{@"type": @"INTEGER", @"default": @10, @"not_null": @YES},
                    @"name": @{@"type": @"TEXT", @"default": @"default_value"},
                    @"weight": @{@"type": @"REAL", @"default": @65.4},
                    @"tall": @{@"type": @"REAL", @"default": @172.4},
                    @"data": @{@"type": @"BLOB"}
                },
                @"relations": @{@"child": @{@"target": @"sample_b"}, @"friend": @{@"target": @"sample_c"}}
            },
            @"sample_b": @{
                @"attributes": @{@"name": @{@"type": @"TEXT"}},
                @"relations": @{@"parent": @{@"target": @"sample_a"}}
            },
            @"sample_c": @{
                @"attributes": @{@"name": @{@"type": @"TEXT"}},
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
