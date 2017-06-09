//
//  yas_db_identifier_tests.mm
//

#import <XCTest/XCTest.h>
#import "yas_db_identifier.h"

using namespace yas;

@interface yas_db_identifier_tests : XCTestCase

@end

@implementation yas_db_identifier_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_stable_id {
    db::identifier stable_id{db::value{1}, false};

    XCTAssertTrue(stable_id);
    XCTAssertTrue(stable_id.is_stable());
    XCTAssertFalse(stable_id.is_temporary());
    XCTAssertEqual(stable_id.stable(), db::value{1});
}

- (void)test_temporary_id {
    db::identifier tmp_id{db::value{2}, true};

    XCTAssertTrue(tmp_id);
    XCTAssertTrue(tmp_id.is_temporary());
    XCTAssertFalse(tmp_id.is_stable());
    XCTAssertEqual(tmp_id.temporary(), db::value{2});
}

- (void)test_make_stable_id {
    auto stable_id = db::make_stable_id(db::value{3});

    XCTAssertEqual(stable_id.stable(), db::value{3});
}

- (void)test_make_temporary_id {
    auto tmp_id = db::make_temporary_id(db::value{4});

    XCTAssertEqual(tmp_id.temporary(), db::value{4});
}

- (void)test_null_id {
    XCTAssertFalse(db::null_id());
}

- (void)test_set_stable {
    db::identifier identifier{db::value{10}, true};

    XCTAssertFalse(identifier.is_stable());

    identifier.set_stable(db::value{20});

    XCTAssertTrue(identifier.is_stable());
    XCTAssertEqual(identifier.stable(), db::value{20});

    identifier.set_stable(30);

    XCTAssertEqual(identifier.stable(), db::value{30});
}

- (void)test_is_equal {
    db::identifier stable_id_a1{db::value{11}, false};
    db::identifier stable_id_a2{db::value{11}, false};
    db::identifier stable_id_b{db::value{22}, false};
    db::identifier tmp_id_a1{db::value{111}, true};
    db::identifier tmp_id_a2{db::value{111}, true};
    db::identifier tmp_id_b{db::value{222}, true};
    db::identifier tmp_to_stable_id{db::value{111}, true};
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

@end
