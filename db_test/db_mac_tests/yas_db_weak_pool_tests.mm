//
//  yas_db_weak_pool_tests.mm
//

#import <XCTest/XCTest.h>
#import <db/yas_db_umbrella.h>

using namespace yas;

@interface yas_db_weak_pool_tests : XCTestCase

@end

@implementation yas_db_weak_pool_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_set_and_get {
    db::weak_pool<std::string, db::value> pool;

    db::value val{1};
    pool.set("entity_a", "key_a", val);

    XCTAssertEqual(pool.get("entity_a", "key_a"), val);
}

- (void)test_get_no_value {
    db::weak_pool<std::string, db::value> pool;

    XCTAssertFalse(pool.get("entity_a", "key_a"));
}

- (void)test_create {
    db::weak_pool<std::string, db::value> pool;

    bool called = false;

    auto val = pool.get_or_create("entity_a", "key_a", [&called]() {
        called = true;
        return db::value{2};
    });

    XCTAssertTrue(called);
    XCTAssertEqual(val, db::value{2});
}

- (void)test_get_exists_value {
    db::weak_pool<std::string, db::value> pool;

    db::value val{3};
    pool.set("entity_a", "key_a", val);

    bool called = false;

    auto get_val = pool.get_or_create("entity_a", "key_a", [&called]() {
        called = true;
        return db::value{4};
    });

    XCTAssertFalse(called);
    XCTAssertEqual(get_val, db::value{3});
    XCTAssertEqual(get_val.identifier(), val.identifier());
}

- (void)test_perform {
    db::weak_pool<std::string, db::value> pool;

    auto a_val_1 = db::value{1};
    auto a_val_2 = db::value{2};
    auto b_val_3 = db::value{3};
    auto b_val_4 = db::value{4};

    pool.set("entity_a", "key_1", a_val_1);
    pool.set("entity_a", "key_2", a_val_2);
    pool.set("entity_b", "key_3", b_val_3);
    pool.set("entity_b", "key_4", b_val_4);

    std::size_t called_count = 0;

    std::unordered_map<std::string, std::unordered_map<std::string, db::value>> called_values;

    pool.perform([&called_count, &called_values](std::string const &entity_name, std::string const &key,
                                                 db::value const &value) {
        if (called_values.count(entity_name) == 0) {
            called_values.emplace(entity_name, std::unordered_map<std::string, db::value>{});
        }

        auto &entity_called_values = called_values.at(entity_name);
        entity_called_values.emplace(key, value);

        ++called_count;
    });

    XCTAssertEqual(called_count, 4);

    XCTAssertEqual(called_values.size(), 2);
    XCTAssertEqual(called_values.at("entity_a").size(), 2);
    XCTAssertEqual(called_values.at("entity_a").at("key_1"), db::value{1});
    XCTAssertEqual(called_values.at("entity_a").at("key_2"), db::value{2});
    XCTAssertEqual(called_values.at("entity_b").size(), 2);
    XCTAssertEqual(called_values.at("entity_b").at("key_3"), db::value{3});
    XCTAssertEqual(called_values.at("entity_b").at("key_4"), db::value{4});
}

- (void)test_perform_entity {
    db::weak_pool<std::string, db::value> pool;

    auto a_val_1 = db::value{1};
    auto a_val_2 = db::value{2};
    auto b_val_3 = db::value{3};
    auto b_val_4 = db::value{4};

    pool.set("entity_a", "key_1", a_val_1);
    pool.set("entity_a", "key_2", a_val_2);
    pool.set("entity_b", "key_3", b_val_3);
    pool.set("entity_b", "key_4", b_val_4);

    std::size_t called_count = 0;

    std::unordered_map<std::string, std::unordered_map<std::string, db::value>> called_values;

    pool.perform_entity("entity_a", [&called_count, &called_values](std::string const &entity_name,
                                                                    std::string const &key, db::value const &value) {
        if (called_values.count(entity_name) == 0) {
            called_values.emplace(entity_name, std::unordered_map<std::string, db::value>{});
        }

        auto &entity_called_values = called_values.at(entity_name);
        entity_called_values.emplace(key, value);

        ++called_count;
    });

    XCTAssertEqual(called_count, 2);

    XCTAssertEqual(called_values.size(), 1);
    XCTAssertEqual(called_values.at("entity_a").size(), 2);
    XCTAssertEqual(called_values.at("entity_a").at("key_1"), db::value{1});
    XCTAssertEqual(called_values.at("entity_a").at("key_2"), db::value{2});
}

- (void)test_release_value {
    db::weak_pool<std::string, db::value> pool;

    {
        auto val = db::value{1};
        pool.set("entity_a", "key_1", val);
    }

    XCTAssertFalse(pool.get("entity_a", "key_1"));
}

- (void)test_erase {
    db::weak_pool<std::string, db::value> pool;

    auto val1 = db::value{1};
    auto val2 = db::value{2};

    pool.set("entity_a", "key_1", val1);
    pool.set("entity_b", "key_2", val2);

    pool.erase("entity_a", "key_1");

    XCTAssertFalse(pool.get("entity_a", "key_1"));
    XCTAssertTrue(pool.get("entity_b", "key_2"));
}

- (void)test_clear {
    db::weak_pool<std::string, db::value> pool;

    auto val1 = db::value{1};
    auto val2 = db::value{2};

    pool.set("entity_a", "key_1", val1);
    pool.set("entity_b", "key_2", val2);

    pool.clear();

    XCTAssertFalse(pool.get("entity_a", "key_1"));
    XCTAssertFalse(pool.get("entity_b", "key_2"));
}

@end
