import Foundation
@testable import ChatDeskMac

/// Runs synchronously like the AppKit entry point, without XCTest or a window.
@main
@MainActor
struct WebAdapterGateHarness {
    static func main() {
        var timeoutResults = 0
        let timeoutGate = WebAdapter.CallGate { result in
            guard case .failure = result else { fatalError("Expected timeout") }
            timeoutResults += 1
        }
        timeoutGate.startWatchdog(after: 0.02, method: "context")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(timeoutResults == 1, "Watchdog must complete in the synchronous main run loop")
        timeoutGate.finish(.success(["ok": true]))
        precondition(timeoutResults == 1, "Late success must not complete twice")

        var successResults = 0
        let successGate = WebAdapter.CallGate { result in
            guard case .success = result else { fatalError("Success must cancel timeout") }
            successResults += 1
        }
        successGate.startWatchdog(after: 0.02, method: "context")
        successGate.finish(.success(["ok": true]))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(successResults == 1, "Cancelled timeout must not complete twice")
        print("PASS: synchronous watchdog, late callback ignored, success cancels timeout")
    }
}
