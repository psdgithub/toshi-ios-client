import XCTest
import UIKit

class Tests: XCTestCase {

    func testExample() {
        let expect = expectation(description: "get ethereum rate")
        EthereumAPIClient.shared.getRate { decimal in
            XCTAssertNotNil(decimal)
            expect.fulfill()

         }

        waitForExpectations(timeout: 100)

    }
}
