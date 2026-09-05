import XCTest
@testable import KanalCore

final class TelevisionSeekStateTests: XCTestCase {
    func testNudgesClampAndCommit() {
        var state = TelevisionSeekState(duration: 100)
        XCTAssertEqual(state.nudge(.backward, from: 3, at: 0), 0)
        XCTAssertEqual(state.nudge(.forward, from: 3, at: 0.1), 10)
        XCTAssertEqual(state.commit(), 10)
        XCTAssertNil(state.pending)
    }

    func testDirectionReversalRestartsFineStep() {
        var state = TelevisionSeekState(duration: 10_000)
        for index in 0..<5 { _ = state.nudge(.forward, from: 0, at: Double(index) * 0.1) }
        XCTAssertEqual(state.nudge(.backward, from: 0, at: 0.6), 50)
        XCTAssertEqual(state.nudge(.backward, from: 0, at: 0.7), 40)
    }

    func testPauseRestartsAccelerationAndCancelClearsPreview() {
        var state = TelevisionSeekState(duration: 10_000)
        for index in 0..<5 { _ = state.nudge(.forward, from: 0, at: Double(index) * 0.1) }
        XCTAssertEqual(state.nudge(.forward, from: 0, at: 1.2), 70)
        state.cancel()
        XCTAssertNil(state.pending)
        XCTAssertEqual(state.nudge(.forward, from: 0, at: 2), 10)
    }
}
