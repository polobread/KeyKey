import Foundation
import XCTest
@testable import KeyKeyEngine

final class SupporterStateTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suite = "SupporterStateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    func testPromptIsHiddenBeforeThirtyDays() {
        let firstUse = Date(timeIntervalSince1970: 1_000_000)
        let now = firstUse.addingTimeInterval(SupporterState.trialDuration - 1)
        XCTAssertFalse(SupporterState.shouldShowSupportPrompt(
            firstUse: firstUse, now: now, supporter: false
        ))
    }

    func testPromptAppearsAtThirtyDaysWithoutPurchase() {
        let firstUse = Date(timeIntervalSince1970: 1_000_000)
        let now = firstUse.addingTimeInterval(SupporterState.trialDuration)
        XCTAssertTrue(SupporterState.shouldShowSupportPrompt(
            firstUse: firstUse, now: now, supporter: false
        ))
    }

    func testSupporterNeverSeesPrompt() {
        let firstUse = Date(timeIntervalSince1970: 1_000_000)
        let now = firstUse.addingTimeInterval(SupporterState.trialDuration * 10)
        XCTAssertFalse(SupporterState.shouldShowSupportPrompt(
            firstUse: firstUse, now: now, supporter: true
        ))
    }

    func testFirstUseAndEntitlementPersist() {
        let state = SupporterState(defaults: defaults)
        let first = Date(timeIntervalSince1970: 1_000_000)
        let later = first.addingTimeInterval(100)

        XCTAssertEqual(state.recordFirstUse(at: first), first)
        XCTAssertEqual(state.recordFirstUse(at: later), first)
        XCTAssertFalse(state.isSupporter)
        state.setSupporter(true)
        XCTAssertTrue(SupporterState(defaults: defaults).isSupporter)
    }
}
