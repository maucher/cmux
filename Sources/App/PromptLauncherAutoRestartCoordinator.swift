import Foundation

/// Cancels one scheduled auto-restart check.
@MainActor
protocol PromptLauncherAutoRestartTimer: AnyObject {
    func cancel()
}

/// Schedules auto-restart checks; injectable so tests control time.
@MainActor
protocol PromptLauncherAutoRestartScheduling {
    func schedule(
        after delay: TimeInterval,
        _ work: @escaping @MainActor () -> Void
    ) -> PromptLauncherAutoRestartTimer
}

@MainActor
final class MainQueuePromptLauncherAutoRestartScheduler: PromptLauncherAutoRestartScheduling {
    private final class Timer: PromptLauncherAutoRestartTimer {
        let item: DispatchWorkItem
        init(item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    func schedule(
        after delay: TimeInterval,
        _ work: @escaping @MainActor () -> Void
    ) -> PromptLauncherAutoRestartTimer {
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return Timer(item: item)
    }
}

/// Restores prompt-launcher remote workspaces after the Mac wakes, the network
/// returns, or a remote pane drops, by running `promptLauncher.autoRestartHook`
/// through the same path as the session-card restart button.
///
/// cmux's own reconnect gets the first try (a grace period), and the hook is
/// expected to leave healthy workspaces alone. Its exit status drives retries:
/// 0 restored or healthy, 3 not managed, 75 unreachable (backoff), anything
/// else a failed restore (two retries, then the card asks for a manual restart).
@MainActor
final class PromptLauncherAutoRestartCoordinator {
    enum Outcome: Equatable {
        case restored
        case unmanaged
        case unreachable
        case failed

        init(exitCode: Int32) {
            switch exitCode {
            case 0: self = .restored
            case 3: self = .unmanaged
            case 75: self = .unreachable
            default: self = .failed
            }
        }
    }

    struct Policy {
        var wakeExtraDelay: TimeInterval = 4
        var surfaceDropDelay: TimeInterval = 3
        /// Pane exits right after a hook run are usually the hook replacing panes.
        var selfInflictedCooldown: TimeInterval = 20
        var unreachableBackoff: [TimeInterval] = [5, 10, 20, 40, 80, 160, 300]
        var unreachableBudget: TimeInterval = 30 * 60
        var failureRetries: [TimeInterval] = [30, 120]
        var rerunDelay: TimeInterval = 1
    }

    private struct Entry {
        var timer: PromptLauncherAutoRestartTimer?
        var dueAt: Date?
        var running = false
        var rerunRequested = false
        var unreachableSince: Date?
        var unreachableAttempts = 0
        var failures = 0
        var lastFinishedAt: Date?

        mutating func resetRetries() {
            unreachableSince = nil
            unreachableAttempts = 0
            failures = 0
        }
    }

    private let workspaceIds: @MainActor () -> [UUID]
    private let isNetworkAvailable: @MainActor () -> Bool
    private let graceSeconds: @MainActor () -> TimeInterval
    private let runHook: @MainActor (UUID, @escaping @MainActor (Int32?) -> Void) -> Void
    private let rearmNativeReconnect: @MainActor () -> Void
    private let gaveUp: @MainActor (UUID) -> Void
    private let scheduler: PromptLauncherAutoRestartScheduling
    private let now: @MainActor () -> Date
    private let policy: Policy

    private var entries: [UUID: Entry] = [:]
    private var waitingForNetwork: Set<UUID> = []
    private var isSuspended = false

    init(
        workspaceIds: @escaping @MainActor () -> [UUID],
        isNetworkAvailable: @escaping @MainActor () -> Bool,
        graceSeconds: @escaping @MainActor () -> TimeInterval,
        runHook: @escaping @MainActor (UUID, @escaping @MainActor (Int32?) -> Void) -> Void,
        rearmNativeReconnect: @escaping @MainActor () -> Void,
        gaveUp: @escaping @MainActor (UUID) -> Void,
        scheduler: PromptLauncherAutoRestartScheduling? = nil,
        now: @escaping @MainActor () -> Date = Date.init,
        policy: Policy = Policy()
    ) {
        self.workspaceIds = workspaceIds
        self.isNetworkAvailable = isNetworkAvailable
        self.graceSeconds = graceSeconds
        self.runHook = runHook
        self.rearmNativeReconnect = rearmNativeReconnect
        self.gaveUp = gaveUp
        self.scheduler = scheduler ?? MainQueuePromptLauncherAutoRestartScheduler()
        self.now = now
        self.policy = policy
    }

    // MARK: Triggers

    func noteSystemWillSleep() {
        isSuspended = true
        for id in Array(entries.keys) {
            entries[id]?.timer?.cancel()
            entries[id]?.timer = nil
            entries[id]?.dueAt = nil
        }
        waitingForNetwork.removeAll()
    }

    func noteSystemWake() {
        isSuspended = false
        let delay = graceSeconds() + policy.wakeExtraDelay
        for id in workspaceIds() {
            request(id, after: delay, resetRetries: true)
        }
    }

    func noteNetworkRestored() {
        guard !isSuspended else { return }
        // A host that stayed unreachable leaves cmux's own reconnect suspended;
        // re-arm it before running the hook.
        rearmNativeReconnect()
        waitingForNetwork.removeAll()
        let delay = graceSeconds()
        for id in workspaceIds() {
            request(id, after: delay, resetRetries: true)
        }
    }

    /// A remote pane's process exited or its persistent reattach failed.
    func noteRemoteSurfaceDropped(workspaceId: UUID) {
        if let entry = entries[workspaceId] {
            if entry.running { return }
            if let finished = entry.lastFinishedAt,
               now().timeIntervalSince(finished) < policy.selfInflictedCooldown {
                return
            }
        }
        guard workspaceIds().contains(workspaceId) else { return }
        request(workspaceId, after: policy.surfaceDropDelay, resetRetries: false)
    }

    /// cmux gave up reconnecting on its own (error or suspended).
    func noteRemoteConnectionLost(workspaceId: UUID) {
        guard workspaceIds().contains(workspaceId) else { return }
        request(workspaceId, after: graceSeconds(), resetRetries: false)
    }

    /// A manual restart supersedes queued automatic retries.
    func cancelPending(workspaceId: UUID) {
        guard var entry = entries[workspaceId] else { return }
        entry.timer?.cancel()
        entry.timer = nil
        entry.dueAt = nil
        entry.resetRetries()
        entries[workspaceId] = entry
        waitingForNetwork.remove(workspaceId)
    }

    // MARK: Scheduling

    private func request(_ id: UUID, after delay: TimeInterval, resetRetries: Bool) {
        guard !isSuspended else { return }
        var entry = entries[id] ?? Entry()
        if resetRetries { entry.resetRetries() }
        if entry.running {
            entry.rerunRequested = true
            entries[id] = entry
            return
        }
        let due = now().addingTimeInterval(delay)
        // Merge bursts of triggers into one run at the latest requested time,
        // which also gives cmux's own reconnect the longest grace.
        if entry.timer != nil, let existing = entry.dueAt, existing >= due {
            entries[id] = entry
            return
        }
        entry.timer?.cancel()
        entry.dueAt = due
        entry.timer = scheduler.schedule(after: delay) { [weak self] in
            self?.fire(id)
        }
        entries[id] = entry
    }

    private func fire(_ id: UUID) {
        guard var entry = entries[id] else { return }
        entry.timer = nil
        entry.dueAt = nil
        guard !isSuspended else {
            entries[id] = entry
            return
        }
        guard workspaceIds().contains(id) else {
            entries.removeValue(forKey: id)
            return
        }
        guard isNetworkAvailable() else {
            waitingForNetwork.insert(id)
            entries[id] = entry
            return
        }
        entry.running = true
        entries[id] = entry
        runHook(id) { [weak self] code in
            self?.finish(id, exitCode: code)
        }
    }

    private func finish(_ id: UUID, exitCode: Int32?) {
        guard var entry = entries[id] else { return }
        entry.running = false
        entry.lastFinishedAt = now()
        let rerun = entry.rerunRequested
        entry.rerunRequested = false
        entries[id] = entry

        guard let exitCode else {
            // Busy (a manual restart is running) or no hook; try once more later.
            if rerun { request(id, after: policy.rerunDelay, resetRetries: false) }
            return
        }
        switch Outcome(exitCode: exitCode) {
        case .restored, .unmanaged:
            entries[id]?.resetRetries()
            if rerun { request(id, after: policy.rerunDelay, resetRetries: false) }
        case .unreachable:
            let since = entry.unreachableSince ?? now()
            guard now().timeIntervalSince(since) < policy.unreachableBudget else {
                entries[id]?.resetRetries()
                gaveUp(id)
                return
            }
            let backoff = policy.unreachableBackoff
            let delay = backoff[min(entry.unreachableAttempts, backoff.count - 1)]
            entries[id]?.unreachableSince = since
            entries[id]?.unreachableAttempts = entry.unreachableAttempts + 1
            request(id, after: rerun ? policy.rerunDelay : delay, resetRetries: false)
        case .failed:
            let failures = entry.failures + 1
            guard failures <= policy.failureRetries.count else {
                entries[id]?.resetRetries()
                gaveUp(id)
                return
            }
            entries[id]?.failures = failures
            request(id, after: policy.failureRetries[failures - 1], resetRetries: false)
        }
    }
}
