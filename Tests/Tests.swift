// Copyright (c) 2017 Token Browser, Inc
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
import XCTest
import UIKit
import Teapot

class AppsAPIClientTests: XCTestCase {
    var subject: AppsAPIClient!

    override func setUp() {
        super.setUp()

        let mockTeapot = MockTeapot(baseURL: URL(string: "https://token-id-service-development.herokuapp.com")!, bundle: Bundle(for: AppsAPIClientTests.self))
        subject = AppsAPIClient(mockTeapot: mockTeapot)
    }

    func testGetFeaturedApps() {
        let expect = self.expectation(description: "test")
        subject.getFeaturedApps { (user, error) in
            XCTAssertNil(error)
            XCTAssertNotNil(user)
            expect.fulfill()
        }
        self.waitForExpectations(timeout: 100)
    }
}