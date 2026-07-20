import Combine
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Sidebar status RPC refresh", .serialized)
@MainActor
struct SidebarStatusRPCRefreshTests {
    @Test
    func setAndClearStatusInvalidateSessionCards() async throws {
        let controller = TerminalController.shared
        let previousManager = controller.activeTabManagerForCallerNotification()
        let manager = TabManager()
        controller.setActiveTabManager(manager)
        defer { controller.setActiveTabManager(previousManager) }

        let workspace = try #require(manager.selectedWorkspace)
        var invalidationCount = 0
        let cancellable = manager.objectWillChange.sink {
            invalidationCount += 1
        }
        defer { cancellable.cancel() }

        let setResponse = try request(
            method: "sidebar.set_status",
            params: [
                "workspace_id": workspace.id.uuidString,
                "key": "status",
                "value": "Working",
                "icon": "bolt.fill",
                "color": "#4C8DFF",
                "priority": "90",
            ]
        )

        #expect(setResponse["ok"] as? Bool == true)
        #expect(SessionCardSnapshot.Status.resolve(workspace: workspace) == .working)
        // Grouping refreshes are coalesced, not synchronous: a status RPC burst
        // must not re-render the sidebar once per call.
        #expect(invalidationCount == 0)

        let clearResponse = try request(
            method: "sidebar.clear_status",
            params: [
                "workspace_id": workspace.id.uuidString,
                "key": "status",
            ]
        )

        #expect(clearResponse["ok"] as? Bool == true)
        #expect(SessionCardSnapshot.Status.resolve(workspace: workspace) == .done)

        try await waitForInvalidation(atLeast: 1) { invalidationCount }
        // The set+clear burst above collapses into a single coalesced refresh.
        #expect(invalidationCount == 1)
    }

    private func waitForInvalidation(
        atLeast expected: Int,
        timeoutSeconds: Double = 2.0,
        count: () -> Int
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while count() < expected, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func request(method: String, params: [String: Any]) throws -> [String: Any] {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "sidebar-status-refresh",
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let line = try #require(String(data: data, encoding: .utf8))
        let response = TerminalController.shared.handleSocketLine(line)
        let responseData = try #require(response.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: responseData) as? [String: Any])
    }
}
