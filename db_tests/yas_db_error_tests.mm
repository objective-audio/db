//
//  yas_db_error_tests.mm
//

#import "yas_db_test_utils.h"

using namespace yas;

@interface yas_db_error_tests : XCTestCase

@end

@implementation yas_db_error_tests

- (void)test_construct_with_type_only {
    db::error error{db::error_type::sqlite};

    XCTAssertEqual(error.type(), db::error_type::sqlite);
    XCTAssertEqual(error.code().raw_value(), SQLITE_OK);
    XCTAssertEqual(error.message(), "");
}

- (void)test_construct_without_message {
    db::error error{db::error_type::in_use, db::sqlite_result_code{SQLITE_INTERNAL}};

    XCTAssertEqual(error.type(), db::error_type::in_use);
    XCTAssertEqual(error.code().raw_value(), SQLITE_INTERNAL);
    XCTAssertEqual(error.message(), "");
}

- (void)test_construct_with_all_parameters {
    db::error error{db::error_type::closed, db::sqlite_result_code{SQLITE_ERROR}, "test_message"};

    XCTAssertEqual(error.type(), db::error_type::closed);
    XCTAssertEqual(error.code().raw_value(), SQLITE_ERROR);
    XCTAssertEqual(error.message(), "test_message");
}

- (void)test_construct_with_nullptr {
    db::error error{nullptr};

    XCTAssertEqual(error.type(), db::error_type::none);
    XCTAssertEqual(error.code().raw_value(), SQLITE_OK);
    XCTAssertEqual(error.message(), "");
}

- (void)test_bool {
    XCTAssertFalse(db::error(db::error_type::none));

    XCTAssertTrue(db::error(db::error_type::closed));
    XCTAssertTrue(db::error(db::error_type::in_use));
    XCTAssertTrue(db::error(db::error_type::invalid_query_count));
    XCTAssertTrue(db::error(db::error_type::invalid_argument));
    XCTAssertTrue(db::error(db::error_type::sqlite));
}

- (void)test_error_to_string {
    db::error error{db::error_type::closed};

    to_string(error);
}

- (void)test_error_ostream {
    auto const values = {db::error_type::closed};

    for (auto const &value : values) {
        std::ostringstream stream;
        stream << value;
        XCTAssertEqual(stream.str(), to_string(value));
    }
}

@end
