import XCTest
@testable import VieLotusCore

private final class MockSecureInputProvider: SecureInputProvider, @unchecked Sendable {
    var stateToReturn = SecureInputState.inactive

    func queryState() -> SecureInputState {
        stateToReturn
    }
}

final class SecureInputMonitorTests: XCTestCase {
    func testMockProviderTransitions() {
        let mock = MockSecureInputProvider()
        let monitor = SecureInputMonitor(provider: mock)

        XCTAssertFalse(monitor.isSecureInputActive)
        XCTAssertEqual(monitor.currentState, .inactive)

        // Simulate password field focus
        mock.stateToReturn = SecureInputState(
            isActive: true,
            holderPID: 9999,
            holderName: "1Password",
            holderBundleID: "com.1password.1password"
        )

        monitor.refresh()
        XCTAssertTrue(monitor.isSecureInputActive)
        XCTAssertEqual(monitor.currentState.holderPID, 9999)
        XCTAssertEqual(monitor.currentState.holderName, "1Password")
        XCTAssertEqual(monitor.currentState.holderBundleID, "com.1password.1password")

        // Simulate password field blur
        mock.stateToReturn = .inactive
        monitor.refresh()
        XCTAssertFalse(monitor.isSecureInputActive)
        XCTAssertNil(monitor.currentState.holderPID)
    }

    func testSystemProviderInstantiatesCleanly() {
        let provider = SystemSecureInputProvider()
        let state = provider.queryState()
        // Running in unit test suite without active password field should be inactive
        // or validly reflect host environment without crashing.
        if state.isActive {
            XCTAssertNotNil(state.holderPID)
        } else {
            XCTAssertFalse(state.isActive)
        }
    }
}
