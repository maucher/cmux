import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class RemoteSessionNetworkPathMonitorTests: XCTestCase {
    private typealias Monitor = RemoteSessionNetworkPathMonitor

    private func path(_ satisfied: Bool, _ interfaces: [String] = ["en0"], _ gateways: [String] = ["192.168.1.1"]) -> Monitor.Snapshot {
        Monitor.snapshot(isSatisfied: satisfied, interfaceNames: interfaces, gateways: gateways)
    }

    func testFirstObservationIsABaseline() {
        XCTAssertFalse(Monitor.shouldReportRestored(previous: nil, current: path(true)))
    }

    func testReconnectingAfterOfflineIsARestore() {
        XCTAssertTrue(Monitor.shouldReportRestored(previous: path(false, [], []), current: path(true)))
    }

    func testSwitchingNetworksWhileOnlineIsARestore() {
        XCTAssertTrue(Monitor.shouldReportRestored(previous: path(true), current: path(true, ["en0"], ["10.0.0.1"])))
        XCTAssertTrue(Monitor.shouldReportRestored(previous: path(true), current: path(true, ["en0", "utun4"])))
    }

    func testDuplicateOrOfflineObservationsAreIgnored() {
        XCTAssertFalse(Monitor.shouldReportRestored(previous: path(true), current: path(true)))
        XCTAssertFalse(Monitor.shouldReportRestored(previous: path(true), current: path(false)))
        XCTAssertFalse(Monitor.shouldReportRestored(
            previous: path(true, ["en0", "utun4"]),
            current: path(true, ["utun4", "en0"])
        ))
    }
}
