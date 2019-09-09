//
//  yas_db_object_id_tests.mm
//

#import <XCTest/XCTest.h>
#import <db/yas_db_object_id.h>

using namespace yas;

@interface yas_db_object_id_tests : XCTestCase

@end

@implementation yas_db_object_id_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_stable_id {
    db::object_id stable_id{db::value{1}, nullptr};

    XCTAssertTrue(stable_id);
    XCTAssertTrue(stable_id.is_stable());
    XCTAssertFalse(stable_id.is_temporary());
    XCTAssertEqual(stable_id.stable_value(), db::value{1});
}

- (void)test_temporary_id {
    db::object_id tmp_id{nullptr, db::value{"2"}};

    XCTAssertTrue(tmp_id);
    XCTAssertTrue(tmp_id.is_temporary());
    XCTAssertFalse(tmp_id.is_stable());
    XCTAssertEqual(tmp_id.temporary(), "2");
}

- (void)test_make_stable_id {
    auto stable_id = db::make_stable_id(db::value{3});

    XCTAssertEqual(stable_id.stable_value(), db::value{3});
}

- (void)test_make_temporary_id {
    auto tmp_id = db::make_temporary_id();

    XCTAssertEqual(tmp_id.temporary(), std::to_string(tmp_id.identifier()));
}

- (void)test_null_id {
    XCTAssertFalse(db::null_id());
}

- (void)test_set_stable {
    db::object_id identifier{nullptr, db::value{"10"}};

    XCTAssertFalse(identifier.is_stable());

    identifier.set_stable(db::value{20});

    XCTAssertTrue(identifier.is_stable());
    XCTAssertEqual(identifier.stable_value(), db::value{20});

    identifier.set_stable(30);

    XCTAssertEqual(identifier.stable_value(), db::value{30});
}

- (void)test_is_equal {
    db::object_id stable_id_a1{db::value{11}, nullptr};
    db::object_id stable_id_a2{db::value{11}, nullptr};
    db::object_id stable_id_b{db::value{22}, nullptr};
    db::object_id tmp_id_a1{nullptr, db::value{"111"}};
    db::object_id tmp_id_a2{nullptr, db::value{"111"}};
    db::object_id tmp_id_b{nullptr, db::value{"222"}};
    db::object_id tmp_to_stable_id{nullptr, db::value{"111"}};
    tmp_to_stable_id.set_stable(11);

    XCTAssertTrue(stable_id_a1 == stable_id_a1);
    XCTAssertTrue(stable_id_a1 == stable_id_a2);
    XCTAssertFalse(stable_id_a1 == stable_id_b);

    XCTAssertTrue(tmp_id_a1 == tmp_id_a1);
    XCTAssertTrue(tmp_id_a1 == tmp_id_a2);
    XCTAssertFalse(tmp_id_a1 == tmp_id_b);

    XCTAssertTrue(tmp_to_stable_id == tmp_id_a1);
    XCTAssertTrue(tmp_to_stable_id == stable_id_a1);
    XCTAssertFalse(tmp_to_stable_id == tmp_id_b);
    XCTAssertFalse(tmp_to_stable_id == stable_id_b);
}

- (void)test_is_stable {
    auto stable_id = db::make_stable_id(db::value{1});

    XCTAssertTrue(stable_id.is_stable());

    auto tmp_id = db::make_temporary_id();

    XCTAssertFalse(tmp_id.is_stable());

    auto each_id = db::object_id{db::value{2}, db::value{"3"}};

    XCTAssertTrue(stable_id.is_stable());
}

- (void)test_is_temporary {
    auto stable_id = db::make_stable_id(db::value{1});

    XCTAssertFalse(stable_id.is_temporary());

    auto tmp_id = db::make_temporary_id();

    XCTAssertTrue(tmp_id.is_temporary());

    auto each_id = db::object_id{db::value{2}, db::value{"3"}};

    XCTAssertFalse(stable_id.is_temporary());
}

- (void)test_copy_temporary {
    auto src = db::make_temporary_id();
    auto dst = src.copy();

    XCTAssertFalse(src.identifier() == dst.identifier());
    XCTAssertTrue(src == dst);
}

- (void)test_copy_stable {
    auto src = db::make_stable_id(db::value{567});
    auto dst = src.copy();

    XCTAssertFalse(src.identifier() == dst.identifier());
    XCTAssertTrue(src == dst);
}

- (void)test_to_string {
    XCTAssertEqual(to_string(db::object_id{db::value{1}, db::value{"2"}}), "{stable:1, temporary:'2'}");
    XCTAssertEqual(to_string(db::object_id{nullptr, db::value{"2"}}), "{stable:null, temporary:'2'}");
    XCTAssertEqual(to_string(db::object_id{db::value{1}, nullptr}), "{stable:1, temporary:null}");
}

@end
