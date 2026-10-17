import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class PromptLauncherAutoRestartCoordinatorTests: XCTestCase {
    private final class FakeTimer: PromptLauncherAutoRestartTimer {
        let due: TimeInterval
        let work: @MainActor () -> Void
        var cancelled = false
        init(due: TimeInterval, work: @escaping @MainActor () -> Void) {
            self.due = due
            self.work = work
        }
        func cancel() { cancelled = true }
    }

    private final class FakeScheduler: PromptLauncherAutoRestartScheduling {
        var now: TimeInterval = 0
        var timers: [FakeTimer] = []

        func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> PromptLauncherAutoRestartTimer {
            let timer = FakeTimer(due: now + delay, work: work)
            timers.append(timer)
            return timer
        }

        var pendingDelays: [TimeInterval] {
            timers.filter { !$0.cancelled }.map { $0.due - now }
        }

        func advance(by seconds: TimeInterval) {
            let target = now + seconds
            while let next = timers.filter({ !$0.cancelled && $0.due <= target }).min(by: { $0.due < $1.due }) {
                now = next.due
                next.cancelled = true
                next.work()
            }
            now = target
        }
    }

    private let workspace = UUID()
    private var scheduler: FakeScheduler!
    private var runs: [UUID] = []
    private var pendingCompletions: [(Int32?) -> Void] = []
    private var exitCodes: [Int32?] = []
    private var networkAvailable = true
    private var gaveUp: [UUID] = []
    private var rearms = 0
    private var managed: [UUID] = []

    override func setUp() {
        super.setUp()
        scheduler = FakeScheduler()
        runs = []
        pendingCompletions = []
        exitCodes = []
        networkAvailable = true
        gaveUp = []
        rearms = 0
        managed = [workspace]
    }

    /// Hooks complete immediately with the next queued exit code, or stay
    /// running when `holdRuns` is set.
    private var holdRuns = false

    private func makeCoordinator() -> PromptLauncherAutoRestartCoordinator {
        PromptLauncherAutoRestartCoordinator(
            workspaceIds: { [unowned self] in managed },
            isNetworkAvailable: { [unowned self] in networkAvailable },
            graceSeconds: { 8 },
            runHook: { [unowned self] id, completion in
                runs.append(id)
                if holdRuns {
                    pendingCompletions.append(completion)
                } else {
                    completion(exitCodes.isEmpty ? 0 : exitCodes.removeFirst())
                }
            },
            rearmNativeReconnect: { [unowned self] in rearms += 1 },
            gaveUp: { [unowned self] id in gaveUp.append(id) },
            scheduler: scheduler,
            now: { [unowned self] in Date(timeIntervalSince1970: scheduler.now) }
        )
    }

    func testWakeWaitsForNativeReconnectGraceThenRunsOnce() {
        let coordinator = makeCoordinator()
        coordinator.noteSystemWake()
        scheduler.advance(by: 11)
        XCTAssertTrue(runs.isEmpty, "cmux's own reconnect gets the grace period first")
        scheduler.advance(by: 1)
        XCTAssertEqual(runs, [workspace])
    }

    func testBurstOfTriggersMergesIntoOneRun() {
        let coordinator = makeCoordinator()
        coordinator.noteSystemWake()
        coordinator.noteNetworkRestored()
        coordinator.noteRemoteSurfaceDropped(workspaceId: workspace)
        scheduler.advance(by: 60)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(rearms, 1)
    }

    func testTriggerWhileRunningRerunsOnceAfterFinish() {
        let coordinator = makeCoordinator()
        holdRuns = true
        coordinator.noteNetworkRestored()
        scheduler.advance(by: 8)
        XCTAssertEqual(runs.count, 1)
        coordinator.noteNetworkRestored()
        coordinator.noteSystemWake()
        holdRuns = false
        pendingCompletions.removeFirst()(0)
        scheduler.advance(by: 1)
        XCTAssertEqual(runs.count, 2)
        scheduler.advance(by: 60)
        XCTAssertEqual(runs.count, 2)
    }

    func testUnreachableBacksOffAndGivesUpAfterBudget() {
        let coordinator = makeCoordinator()
        exitCodes = Array(repeating: 75, count: 40)
        coordinator.noteNetworkRestored()
        scheduler.advance(by: 8)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(scheduler.pendingDelays, [5])
        scheduler.advance(by: 5)
        XCTAssertEqual(scheduler.pendingDelays, [10])
        scheduler.advance(by: 10)
        XCTAssertEqual(scheduler.pendingDelays, [20])
        scheduler.advance(by: 3600)
        XCTAssertEqual(gaveUp, [workspace])
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        XCTAssertLessThan(runs.count, 15, "backoff caps at five minutes")
    }

    func testOfflinePausesUntilNetworkReturns() {
        let coordinator = makeCoordinator()
        networkAvailable = false
        coordinator.noteSystemWake()
        scheduler.advance(by: 600)
        XCTAssertTrue(runs.isEmpty)
        networkAvailable = true
        coordinator.noteNetworkRestored()
        scheduler.advance(by: 8)
        XCTAssertEqual(runs, [workspace])
    }

    func testFailedRestoreRetriesTwiceThenAsksForManualRestart() {
        let coordinator = makeCoordinator()
        exitCodes = [1, 1, 1]
        coordinator.noteRemoteConnectionLost(workspaceId: workspace)
        scheduler.advance(by: 8)
        scheduler.advance(by: 30)
        scheduler.advance(by: 120)
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(gaveUp, [workspace])
        scheduler.advance(by: 600)
        XCTAssertEqual(runs.count, 3)
    }

    func testUnmanagedWorkspaceIsNotRetried() {
        let coordinator = makeCoordinator()
        exitCodes = [3]
        coordinator.noteSystemWake()
        scheduler.advance(by: 600)
        XCTAssertEqual(runs.count, 1)
        XCTAssertTrue(gaveUp.isEmpty)
    }

    func testPaneExitsRightAfterAHookRunAreIgnored() {
        let coordinator = makeCoordinator()
        coordinator.noteNetworkRestored()
        scheduler.advance(by: 8)
        XCTAssertEqual(runs.count, 1)
        coordinator.noteRemoteSurfaceDropped(workspaceId: workspace)
        scheduler.advance(by: 60)
        XCTAssertEqual(runs.count, 1, "the hook replacing panes must not retrigger itself")
        coordinator.noteRemoteSurfaceDropped(workspaceId: workspace)
        scheduler.advance(by: 3)
        XCTAssertEqual(runs.count, 2)
    }

    func testManualRestartCancelsPendingRetry() {
        let coordinator = makeCoordinator()
        exitCodes = [75]
        coordinator.noteNetworkRestored()
        scheduler.advance(by: 8)
        XCTAssertEqual(scheduler.pendingDelays, [5])
        coordinator.cancelPending(workspaceId: workspace)
        scheduler.advance(by: 600)
        XCTAssertEqual(runs.count, 1)
    }

    func testSleepCancelsPendingWorkAndIgnoresTriggers() {
        let coordinator = makeCoordinator()
        coordinator.noteRemoteConnectionLost(workspaceId: workspace)
        coordinator.noteSystemWillSleep()
        coordinator.noteNetworkRestored()
        scheduler.advance(by: 600)
        XCTAssertTrue(runs.isEmpty)
        coordinator.noteSystemWake()
        scheduler.advance(by: 12)
        XCTAssertEqual(runs.count, 1)
    }

    func testNoConfiguredHookMeansNothingRuns() {
        managed = []
        let coordinator = makeCoordinator()
        coordinator.noteSystemWake()
        coordinator.noteNetworkRestored()
        coordinator.noteRemoteSurfaceDropped(workspaceId: workspace)
        scheduler.advance(by: 600)
        XCTAssertTrue(runs.isEmpty)
    }

    func testExitCodeMapping() {
        XCTAssertEqual(PromptLauncherAutoRestartCoordinator.Outcome(exitCode: 0), .restored)
        XCTAssertEqual(PromptLauncherAutoRestartCoordinator.Outcome(exitCode: 3), .unmanaged)
        XCTAssertEqual(PromptLauncherAutoRestartCoordinator.Outcome(exitCode: 75), .unreachable)
        XCTAssertEqual(PromptLauncherAutoRestartCoordinator.Outcome(exitCode: 2), .failed)
    }

    func testPromptLauncherDecodesAutoRestartHook() throws {
        let json = """
        {"command": "ws {{prompt}}",
         "targets": [{"id": "devbox", "args": ["devbox"]}],
         "providers": [{"id": "claude", "args": []}],
         "restartHook": "ws restart --from-card --workspace {{workspace.id}}",
         "autoRestartHook": "  ws restart --from-card --auto --workspace {{workspace.id}}  ",
         "autoRestartGraceSeconds": 12}
        """
        let launcher = try JSONDecoder().decode(CmuxPromptLauncherDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(launcher.autoRestartHook, "ws restart --from-card --auto --workspace {{workspace.id}}")
        XCTAssertEqual(launcher.autoRestartGraceSeconds, 12)
        let defaults = try JSONDecoder().decode(CmuxPromptLauncherDefinition.self, from: Data(#"{"command": "ws", "targets": [{"id": "devbox", "args": []}], "providers": [{"id": "claude", "args": []}]}"#.utf8))
        XCTAssertNil(defaults.autoRestartHook)
        XCTAssertEqual(defaults.autoRestartGraceSeconds, CmuxPromptLauncherDefinition.defaultAutoRestartGraceSeconds)
        let roundTrip = try JSONDecoder().decode(
            CmuxPromptLauncherDefinition.self,
            from: JSONEncoder().encode(launcher)
        )
        XCTAssertEqual(roundTrip, launcher)
    }
}
