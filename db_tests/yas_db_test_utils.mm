//
//  yas_db_test_utils.m
//

#import "yas_db_test_utils.h"

using namespace yas;

@implementation yas_db_test_utils

+ (db::database_ptr)create_test_database {
    NSString *databasePath = [[self class] databasePath];
    std::string db_path = yas::to_string((__bridge CFStringRef)databasePath);
    return db::database::make_shared(db_path);
}

+ (db::manager_ptr)create_test_manager {
    return [self create_test_manager:[self model_0_0_0]];
}

+ (db::manager_ptr)create_test_manager:(db::model const &)model {
    return [self create_test_manager:model priority_count:1];
}

+ (yas::db::manager_ptr)create_test_manager:(yas::db::model const &)model priority_count:(size_t)count {
    NSString *databasePath = [[self class] databasePath];
    std::string db_path = yas::to_string((__bridge CFStringRef)databasePath);
    return db::manager::make_shared(db_path, model, count);
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

+ (yas::db::model)model_0_0_0 {
    yas::version version{"0.0.0"};

    return db::model{db::model_args{.version = std::move(version), .entities = {}, .indices = {}}};
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
        .relations = {{.name = "child", .target = "sample_b"}}};

    db::entity_args sample_b{.name = "sample_b", .attributes = {{.name = "name", .type = db::attribute_type::text}}};

    db::entity_args_vector_t entities{std::move(sample_a), std::move(sample_b)};

    db::index_args sample_a_name_index{.name = "sample_a_name", .entity = "sample_a", .attributes = {"name"}};
    db::index_args sample_a_others_index{
        .name = "sample_a_others", .entity = "sample_a", .attributes = {"age", "weight"}};

    db::index_args_vector_t indices{std::move(sample_a_name_index), std::move(sample_a_others_index)};

    return db::model{
        db::model_args{.version = std::move(version), .entities = std::move(entities), .indices = std::move(indices)}};
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
        .relations = {{.name = "child", .target = "sample_b"}, {.name = "friend", .target = "sample_c"}}};

    db::entity_args sample_b{.name = "sample_b",
                             .attributes = {{.name = "name", .type = db::attribute_type::text}},
                             .relations = {{.name = "parent", .target = "sample_a"}}};

    db::entity_args sample_c{.name = "sample_c",
                             .attributes = {{.name = "name", .type = db::attribute_type::text}},
                             .relations = {{.name = "friend", .target = "sample_a"}}};

    db::entity_args_vector_t entities{std::move(sample_a), std::move(sample_b), std::move(sample_c)};

    db::index_args sample_a_name_index{.name = "sample_a_name", .entity = "sample_a", .attributes = {"name"}};
    db::index_args sample_a_others_index{
        .name = "sample_a_others", .entity = "sample_a", .attributes = {"age", "weight"}};
    db::index_args sample_b_name_index{.name = "sample_b_name", .entity = "sample_b", .attributes = {"name"}};

    db::index_args_vector_t indices{std::move(sample_a_name_index), std::move(sample_a_others_index),
                                    std::move(sample_b_name_index)};

    return db::model{
        db::model_args{.version = std::move(version), .entities = std::move(entities), .indices = std::move(indices)}};
}

@end
