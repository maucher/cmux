import CmuxCloud
import Foundation

extension AppDelegate {
    func prepareRemoteSessionsForSystemSleep() {
        forEachRemoteWorkspace { workspace in
            workspace.prepareRemoteSessionForSystemSleep()
        }
    }

    func rearmRemoteSessionsAfterSystemWake() {
        // `DisableRemoteConnections` (MDM): a profile that landed while the
        // Mac slept must not be pre-empted by the wake re-arm; the enforcement
        // observer disconnects these workspaces on its next re-evaluation.
        guard ManagedRemoteConnectionsPolicy.isEnabled else { return }
        forEachRemoteWorkspace { workspace in
            workspace.rearmRemoteSessionAfterSystemWake()
        }
    }

    /// Wires prompt-launcher auto-restart to wake, network and pane-drop events.
    func installPromptLauncherAutoRestart() {
        guard promptLauncherAutoRestartCoordinator == nil else { return }
        let coordinator = PromptLauncherAutoRestartCoordinator(
            workspaceIds: { [weak self] in
                self?.remoteSessionTabManagers().flatMap { $0.promptLauncherAutoRestartWorkspaceIds() } ?? []
            },
            isNetworkAvailable: { [weak self] in
                self?.remoteSessionNetworkPathMonitor?.isSatisfied ?? true
            },
            graceSeconds: { [weak self] in
                self?.remoteSessionTabManagers().lazy
                    .compactMap { $0.cmuxConfigStore?.promptLauncher?.autoRestartGraceSeconds }
                    .first ?? CmuxPromptLauncherDefinition.defaultAutoRestartGraceSeconds
            },
            runHook: { [weak self] workspaceId, completion in
                guard let manager = self?.remoteSessionTabManager(containing: workspaceId) else {
                    completion(nil)
                    return
                }
                Task { @MainActor in
                    completion(await manager.runPromptLauncherAutoRestartHook(workspaceId: workspaceId))
                }
            },
            rearmNativeReconnect: { [weak self] in
                self?.rearmRemoteSessionsAfterSystemWake()
            },
            gaveUp: { [weak self] workspaceId in
                self?.remoteSessionTabManager(containing: workspaceId)?
                    .showPromptLauncherAutoRestartGaveUp(workspaceId: workspaceId)
            }
        )
        promptLauncherAutoRestartCoordinator = coordinator
        let monitor = RemoteSessionNetworkPathMonitor { [weak coordinator] in
            coordinator?.noteNetworkRestored()
        }
        remoteSessionNetworkPathMonitor = monitor
        monitor.start()
    }

    private func remoteSessionTabManager(containing workspaceId: UUID) -> TabManager? {
        remoteSessionTabManagers().first { manager in manager.tabs.contains { $0.id == workspaceId } }
    }

    private func remoteSessionTabManagers() -> [TabManager] {
        var seenManagers = Set<ObjectIdentifier>()
        let managers = [tabManager].compactMap { $0 } + allMainWindowTabManagersForDebug()
        return managers.filter { seenManagers.insert(ObjectIdentifier($0)).inserted }
    }

    private func forEachRemoteWorkspace(_ body: (Workspace) -> Void) {
        for manager in remoteSessionTabManagers() {
            for workspace in manager.tabs where workspace.isRemoteWorkspace {
                body(workspace)
            }
        }
    }
}
