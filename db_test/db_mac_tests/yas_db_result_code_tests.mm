//
//  yas_result_code_tests.mm
//

#import "yas_db_test_utils.h"

@interface yas_result_code_tests : XCTestCase

@end

@implementation yas_result_code_tests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)test_create {
    yas::db::result_code code{SQLITE_DONE};

    XCTAssertEqual(code.raw_value(), SQLITE_DONE);
}

- (void)test_to_string {
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_ROW}), "SQLITE_ROW");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_DONE}), "SQLITE_DONE");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_OK}), "SQLITE_OK");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_ERROR}), "SQLITE_ERROR");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_INTERNAL}), "SQLITE_INTERNAL");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_PERM}), "SQLITE_PERM");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_ABORT}), "SQLITE_ABORT");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_BUSY}), "SQLITE_BUSY");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_LOCKED}), "SQLITE_LOCKED");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_NOMEM}), "SQLITE_NOMEM");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_READONLY}), "SQLITE_READONLY");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_INTERRUPT}), "SQLITE_INTERRUPT");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_IOERR}), "SQLITE_IOERR");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_CORRUPT}), "SQLITE_CORRUPT");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_NOTFOUND}), "SQLITE_NOTFOUND");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_FULL}), "SQLITE_FULL");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_CANTOPEN}), "SQLITE_CANTOPEN");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_PROTOCOL}), "SQLITE_PROTOCOL");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_EMPTY}), "SQLITE_EMPTY");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_SCHEMA}), "SQLITE_SCHEMA");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_TOOBIG}), "SQLITE_TOOBIG");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_CONSTRAINT}), "SQLITE_CONSTRAINT");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_MISMATCH}), "SQLITE_MISMATCH");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_MISUSE}), "SQLITE_MISUSE");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_NOLFS}), "SQLITE_NOLFS");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_AUTH}), "SQLITE_AUTH");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_FORMAT}), "SQLITE_FORMAT");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_RANGE}), "SQLITE_RANGE");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_NOTADB}), "SQLITE_NOTADB");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_NOTICE}), "SQLITE_NOTICE");
    XCTAssertEqual(yas::to_string(yas::db::result_code{SQLITE_WARNING}), "SQLITE_WARNING");

    XCTAssertEqual(yas::to_string(yas::db::result_code{10000}), "unknown");
}

@end
