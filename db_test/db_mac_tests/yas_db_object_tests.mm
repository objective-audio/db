//
//  yas_db_object_tests.mm
//

#import <XCTest/XCTest.h>
#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_object_tests : XCTestCase

@end

@implementation yas_db_object_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);

    db::object obj{model, "sample_a"};

    XCTAssertEqual(obj.model(), model);
    XCTAssertEqual(obj.entity_name(), "sample_a");
    XCTAssertEqual(obj.get("age"), nullptr);
    XCTAssertEqual(obj.get("name"), nullptr);
    XCTAssertEqual(obj.get("weight"), nullptr);
    XCTAssertEqual(obj.object_id(), nullptr);
    XCTAssertFalse(obj.is_removed());
}

- (void)test_load {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{model, "sample_a"};

    db::column_map values{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                          std::make_pair("weight", db::value{53.4}), std::make_pair("hoge", db::value{"hage"})};

    obj.load(values);

    XCTAssertEqual(obj.get("age"), db::value{10});
    XCTAssertEqual(obj.get("name"), db::value{"name_val"});
    XCTAssertEqual(obj.get("weight"), db::value{53.4});
    XCTAssertEqual(obj.get("hoge"), nullptr);
}

- (void)test_reload {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{model, "sample_a"};

    db::column_map prev_values{std::make_pair("age", db::value{10}), std::make_pair("name", db::value{"name_val"}),
                               std::make_pair("weight", db::value{53.4}), std::make_pair("hoge", db::value{"hage"})};

    obj.load(prev_values);

    db::column_map post_values{std::make_pair("age", db::value{543}), std::make_pair("hoge", db::value{"poke"})};

    obj.load(post_values);

    XCTAssertEqual(obj.get("age"), db::value{543});
    XCTAssertEqual(obj.get("name"), nullptr);
    XCTAssertEqual(obj.get("weight"), nullptr);
    XCTAssertEqual(obj.get("hoge"), nullptr);
}

- (void)test_set_and_get {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{model, "sample_a"};

    obj.set("age", db::value{24});
    obj.set("name", db::value{"nabe"});
    obj.set("weight", db::value{5783.23});

    XCTAssertEqual(obj.get("age"), db::value{24});
    XCTAssertEqual(obj.get("name"), db::value{"nabe"});
    XCTAssertEqual(obj.get("weight"), db::value{5783.23});
}

- (void)test_replace {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{model, "sample_a"};

    obj.set("age", db::value{1});

    XCTAssertEqual(obj.get("age"), db::value{1});

    obj.set("age", db::value{5});

    XCTAssertEqual(obj.get("age"), db::value{5});
}

- (void)test_remove {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{model, "sample_a"};

    XCTAssertFalse(obj.is_removed());

    obj.set(db::id_field, db::value{11});
    obj.set(db::object_id_field, db::value{45});
    obj.set("name", db::value{"tanaka"});

    XCTAssertEqual(obj.get(db::object_id_field), db::value{45});
    XCTAssertEqual(obj.get("name"), db::value{"tanaka"});

    obj.remove();

    XCTAssertTrue(obj.is_removed());
    XCTAssertEqual(obj.get("name"), nullptr);
    XCTAssertEqual(obj.get(db::id_field), db::value{11});
    XCTAssertEqual(obj.get(db::object_id_field), db::value{45});
}

- (void)test_parameters_for_save {
    NSDictionary *model_dict = [yas_db_test_utils model_dictionary_0_0_1];
    db::model model((__bridge CFDictionaryRef)model_dict);
    db::object obj{model, "sample_a"};

    obj.set(db::id_field, db::value{22});
    obj.set(db::object_id_field, db::value{55});
    obj.set("name", db::value{"suzuki"});
    obj.set("age", db::value{32});
    obj.set("weight", db::value{90.1});
    obj.set("data", db::value::empty());
    obj.set(db::save_id_field, db::value{100});

    auto params = obj.parameters_for_save();

    XCTAssertGreaterThan(params.size(), 6);
    XCTAssertEqual(params.count(db::id_field), 1);
    XCTAssertEqual(params.at(db::id_field), db::value{22});
    XCTAssertEqual(params.count(db::object_id_field), 1);
    XCTAssertEqual(params.at(db::object_id_field), db::value{55});
    XCTAssertEqual(params.count("name"), 1);
    XCTAssertEqual(params.at("name"), db::value{"suzuki"});
    XCTAssertEqual(params.count("age"), 1);
    XCTAssertEqual(params.at("age"), db::value{32});
    XCTAssertEqual(params.count("weight"), 1);
    XCTAssertEqual(params.at("weight"), db::value{90.1});
    XCTAssertEqual(params.count("data"), 1);
    XCTAssertEqual(params.at("data"), db::value::empty());

    XCTAssertEqual(params.count(db::save_id_field), 0);
}

@end
