import XCTest

@MainActor
final class CoachChatUITests: XCTestCase {
    func testCoachChatOpensAndComposerIsReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let coachTab = app.tabBars.buttons["Coach"]
        XCTAssertTrue(coachTab.waitForExistence(timeout: 8))
        coachTab.tap()

        let chatButton = app.buttons["Chat with your coach"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 8))
        chatButton.tap()

        let messageField = app.textFields["Message"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 8))

        messageField.tap()
        messageField.typeText("What should I focus on this week?")

        let sendButton = app.buttons["Send message"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 4))
        XCTAssertTrue(sendButton.isEnabled)

        app.swipeUp()
        app.swipeDown()
    }
}
