//
//  MangoxUITests.swift
//  MangoxUITests
//
//  Created by Abraham Chalita on 02/03/26.
//

import XCTest

@MainActor
final class MangoxUITests: XCTestCase {



    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
