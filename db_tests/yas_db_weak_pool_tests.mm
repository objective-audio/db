//
//  yas_db_weak_pool_tests.mm
//

#import <XCTest/XCTest.h>
#import <db/yas_db_umbrella.h>

using namespace yas;

namespace yas::db::test {
    struct weakable_value : yas::weakable<weakable_value> {
        struct impl : weakable_impl {
            int _value = 0;
            
            impl(int const value) : _value(value) {
            }
        };
        
        weakable_value(int value) : _impl(std::make_shared<impl>(value)) {
        }
        
        weakable_value(std::shared_ptr<weakable_impl> &&wimpl) : _impl(std::dynamic_pointer_cast<impl>(wimpl)) {
        }
        
        void set_value(int const value) {
            this->_impl->_value = value;
        }
        
        int get_value() {
            return this->_impl->_value;
        }
        
        std::shared_ptr<weakable_impl> weakable_impl_ptr() const override {
            return this->_impl;
        }
        
        bool operator==(weakable_value const &rhs) const {
            return this->_impl->_value == rhs._impl->_value;
        }
        
        bool operator!=(weakable_value const &rhs) const {
            return !(*this == rhs);
        }
        
        uintptr_t identifier() {
            return reinterpret_cast<uintptr_t>(this->_impl.get());
        }
        
        std::shared_ptr<impl> _impl;
    };
}

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
    db::weak_pool<std::string, db::test::weakable_value> pool;

    db::test::weakable_value val{1};
    pool.set("entity_a", "key_a", val);

    XCTAssertEqual(pool.get("entity_a", "key_a"), val);
}

- (void)test_get_no_value {
    db::weak_pool<std::string, db::test::weakable_value> pool;

    XCTAssertFalse(pool.get("entity_a", "key_a"));
}

- (void)test_create {
    db::weak_pool<std::string, db::test::weakable_value> pool;

    bool called = false;

    auto val = pool.get_or_create("entity_a", "key_a", [&called]() {
        called = true;
        return db::test::weakable_value{2};
    });

    XCTAssertTrue(called);
    XCTAssertEqual(val, db::test::weakable_value{2});
}

- (void)test_get_exists_value {
    db::weak_pool<std::string, db::test::weakable_value> pool;

    db::test::weakable_value val{3};
    pool.set("entity_a", "key_a", val);

    bool called = false;

    auto get_val = pool.get_or_create("entity_a", "key_a", [&called]() {
        called = true;
        return db::test::weakable_value{4};
    });

    XCTAssertFalse(called);
    XCTAssertEqual(get_val, db::test::weakable_value{3});
    XCTAssertEqual(get_val.identifier(), val.identifier());
}

- (void)test_perform {
    db::weak_pool<std::string, db::test::weakable_value> pool;

    auto a_val_1 = db::test::weakable_value{1};
    auto a_val_2 = db::test::weakable_value{2};
    auto b_val_3 = db::test::weakable_value{3};
    auto b_val_4 = db::test::weakable_value{4};

    pool.set("entity_a", "key_1", a_val_1);
    pool.set("entity_a", "key_2", a_val_2);
    pool.set("entity_b", "key_3", b_val_3);
    pool.set("entity_b", "key_4", b_val_4);

    std::size_t called_count = 0;

    std::unordered_map<std::string, std::unordered_map<std::string, db::test::weakable_value>> called_values;

    pool.perform([&called_count, &called_values](std::string const &entity_name, std::string const &key,
                                                 db::test::weakable_value const &value) {
        if (called_values.count(entity_name) == 0) {
            called_values.emplace(entity_name, std::unordered_map<std::string, db::test::weakable_value>{});
        }

        auto &entity_called_values = called_values.at(entity_name);
        entity_called_values.emplace(key, value);

        ++called_count;
    });

    XCTAssertEqual(called_count, 4);

    XCTAssertEqual(called_values.size(), 2);
    XCTAssertEqual(called_values.at("entity_a").size(), 2);
    XCTAssertEqual(called_values.at("entity_a").at("key_1"), db::test::weakable_value{1});
    XCTAssertEqual(called_values.at("entity_a").at("key_2"), db::test::weakable_value{2});
    XCTAssertEqual(called_values.at("entity_b").size(), 2);
    XCTAssertEqual(called_values.at("entity_b").at("key_3"), db::test::weakable_value{3});
    XCTAssertEqual(called_values.at("entity_b").at("key_4"), db::test::weakable_value{4});
}

- (void)test_perform_entity {
    db::weak_pool<std::string, db::test::weakable_value> pool;

    auto a_val_1 = db::test::weakable_value{1};
    auto a_val_2 = db::test::weakable_value{2};
    auto b_val_3 = db::test::weakable_value{3};
    auto b_val_4 = db::test::weakable_value{4};

    pool.set("entity_a", "key_1", a_val_1);
    pool.set("entity_a", "key_2", a_val_2);
    pool.set("entity_b", "key_3", b_val_3);
    pool.set("entity_b", "key_4", b_val_4);

    std::size_t called_count = 0;

    std::unordered_map<std::string, std::unordered_map<std::string, db::test::weakable_value>> called_values;

    pool.perform_entity("entity_a", [&called_count, &called_values](std::string const &entity_name,
                                                                    std::string const &key, db::test::weakable_value const &value) {
        if (called_values.count(entity_name) == 0) {
            called_values.emplace(entity_name, std::unordered_map<std::string, db::test::weakable_value>{});
        }

        auto &entity_called_values = called_values.at(entity_name);
        entity_called_values.emplace(key, value);

        ++called_count;
    });

    XCTAssertEqual(called_count, 2);

    XCTAssertEqual(called_values.size(), 1);
    XCTAssertEqual(called_values.at("entity_a").size(), 2);
    XCTAssertEqual(called_values.at("entity_a").at("key_1"), db::test::weakable_value{1});
    XCTAssertEqual(called_values.at("entity_a").at("key_2"), db::test::weakable_value{2});
}

- (void)test_release_value {
    db::weak_pool<std::string, db::test::weakable_value> pool;

    {
        auto val = db::test::weakable_value{1};
        pool.set("entity_a", "key_1", val);
    }

    XCTAssertFalse(pool.get("entity_a", "key_1"));
}

- (void)test_erase {
    db::weak_pool<std::string, db::test::weakable_value> pool;

    auto val1 = db::test::weakable_value{1};
    auto val2 = db::test::weakable_value{2};

    pool.set("entity_a", "key_1", val1);
    pool.set("entity_b", "key_2", val2);

    pool.erase("entity_a", "key_1");

    XCTAssertFalse(pool.get("entity_a", "key_1"));
    XCTAssertTrue(pool.get("entity_b", "key_2"));
}

- (void)test_clear {
    db::weak_pool<std::string, db::test::weakable_value> pool;

    auto val1 = db::test::weakable_value{1};
    auto val2 = db::test::weakable_value{2};

    pool.set("entity_a", "key_1", val1);
    pool.set("entity_b", "key_2", val2);

    pool.clear();

    XCTAssertFalse(pool.get("entity_a", "key_1"));
    XCTAssertFalse(pool.get("entity_b", "key_2"));
}

@end
