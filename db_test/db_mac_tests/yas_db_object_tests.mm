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
}

- (void)test_load_attributes {
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

@end
