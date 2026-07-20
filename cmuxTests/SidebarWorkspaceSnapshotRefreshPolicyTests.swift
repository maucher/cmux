import AppKit
import SwiftUI
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class SidebarWorkspaceSnapshotRefreshPolicyTests: XCTestCase {
    func testContextMenuPinChangeUpdatesDisplayedFieldsAndDefersNoisyFields() {
        let current = Self.snapshot(
            title: "lmao",
            isPinned: false,
            customColorHex: nil,
            remoteConnectionStatusText: "Connected",
            latestConversationMessage: "old message",
            listeningPorts: [3000]
        )
        let next = Self.snapshot(
            title: "lmao",
            isPinned: true,
            customColorHex: nil,
            remoteConnectionStatusText: "Disconnected",
            latestConversationMessage: "new message",
            listeningPorts: [3000, 4000]
        )

        let decision = SidebarWorkspaceSnapshotRefreshPolicy.decision(
            current: current,
            next: next,
            force: false,
            contextMenuVisible: true
        )

        var expectedDisplayed = current
        expectedDisplayed = expectedDisplayed.applyingContextMenuImmediateFields(from: next)
        XCTAssertEqual(decision.workspaceSnapshotStorage, expectedDisplayed)
        XCTAssertTrue(decision.workspaceSnapshotStorage?.isPinned == true)
        XCTAssertEqual(decision.workspaceSnapshotStorage?.remoteConnectionStatusText, "Connected")
        XCTAssertEqual(decision.workspaceSnapshotStorage?.latestConversationMessage, "old message")
        XCTAssertEqual(decision.workspaceSnapshotStorage?.listeningPorts, [3000])
        XCTAssertEqual(decision.pendingWorkspaceSnapshot, next)
        XCTAssertTrue(decision.hasDeferredWorkspaceObservationInvalidation)
    }

    func testContextMenuImmediateOnlyChangeDoesNotCreateDeferredFlush() {
        let current = Self.snapshot(
            title: "old",
            customDescription: nil,
            isPinned: false,
            customColorHex: nil
        )
        let next = Self.snapshot(
            title: "new",
            customDescription: "description",
            isPinned: true,
            customColorHex: "#C0392B"
        )

        let decision = SidebarWorkspaceSnapshotRefreshPolicy.decision(
            current: current,
            next: next,
            force: false,
            contextMenuVisible: true
        )

        XCTAssertEqual(decision.workspaceSnapshotStorage, next)
        XCTAssertNil(decision.pendingWorkspaceSnapshot)
        XCTAssertFalse(decision.hasDeferredWorkspaceObservationInvalidation)
    }

    func testClosedContextMenuStoresNextAndClearsPending() {
        let current = Self.snapshot(title: "old", isPinned: false)
        let next = Self.snapshot(title: "new", isPinned: true)

        let decision = SidebarWorkspaceSnapshotRefreshPolicy.decision(
            current: current,
            next: next,
            force: false,
            contextMenuVisible: false
        )

        XCTAssertEqual(decision.workspaceSnapshotStorage, next)
        XCTAssertNil(decision.pendingWorkspaceSnapshot)
        XCTAssertFalse(decision.hasDeferredWorkspaceObservationInvalidation)
    }

    private static func snapshot(
        presentationKey: SidebarWorkspaceSnapshotBuilder.PresentationKey? = nil,
        title: String = "workspace",
        customDescription: String? = nil,
        isPinned: Bool = false,
        customColorHex: String? = nil,
        remoteConnectionStatusText: String = "Disconnected",
        latestConversationMessage: String? = nil,
        listeningPorts: [Int] = []
    ) -> SidebarWorkspaceSnapshotBuilder.Snapshot {
        SidebarWorkspaceSnapshotBuilder.Snapshot(
            presentationKey: presentationKey ?? Self.presentationKey(),
            title: title,
            customDescription: customDescription,
            isPinned: isPinned,
            customColorHex: customColorHex,
            remoteWorkspaceSidebarText: nil,
            remoteConnectionStatusText: remoteConnectionStatusText,
            remoteStateHelpText: "",
            copyableSidebarSSHError: nil,
            latestConversationMessage: latestConversationMessage,
            metadataEntries: [],
            metadataBlocks: [],
            latestLog: nil,
            progress: nil,
            compactGitBranchSummaryText: nil,
            compactDirectoryCandidates: [],
            compactBranchDirectoryCandidates: [],
            branchDirectoryLines: [],
            branchLinesContainBranch: false,
            pullRequestRows: [],
            listeningPorts: listeningPorts
        )
    }

    private static func presentationKey(
        showsWorkspaceDescription: Bool = true,
        usesVerticalBranchLayout: Bool = true,
        showsGitBranch: Bool = true,
        usesViewportAwarePath: Bool = false,
        visibleAuxiliaryDetails: SidebarWorkspaceAuxiliaryDetailVisibility = SidebarWorkspaceAuxiliaryDetailVisibility(
            showsMetadata: true,
            showsLog: true,
            showsProgress: true,
            showsBranchDirectory: true,
            showsPullRequests: true,
            showsPorts: true
        )
    ) -> SidebarWorkspaceSnapshotBuilder.PresentationKey {
        SidebarWorkspaceSnapshotBuilder.PresentationKey(
            showsWorkspaceDescription: showsWorkspaceDescription,
            usesVerticalBranchLayout: usesVerticalBranchLayout,
            showsGitBranch: showsGitBranch,
            usesViewportAwarePath: usesViewportAwarePath,
            visibleAuxiliaryDetails: visibleAuxiliaryDetails
        )
    }
}

final class SessionCardSnapshotTests: XCTestCase {
    func testModeParsingFallsBackToDefault() {
        XCTAssertEqual(SessionCardSnapshot.Mode(metadataValue: "Plan"), .plan)
        XCTAssertEqual(SessionCardSnapshot.Mode(metadataValue: "permission_edit"), .edit)
        XCTAssertEqual(SessionCardSnapshot.Mode(metadataValue: "anything else"), .defaultMode)
        XCTAssertEqual(SessionCardSnapshot.Mode(metadataValue: nil), .defaultMode)
    }

    func testStatusParsingRecognizesAgentLifecycleWords() {
        XCTAssertEqual(SessionCardSnapshot.Status(metadataValue: "working"), .working)
        XCTAssertEqual(SessionCardSnapshot.Status(metadataValue: "needs_input"), .needsInput)
        XCTAssertEqual(SessionCardSnapshot.Status(metadataValue: "ready"), .ready)
        XCTAssertEqual(SessionCardSnapshot.Status(metadataValue: "idle"), .ready)
        XCTAssertEqual(SessionCardSnapshot.Status(metadataValue: "connected"), .ready)
        XCTAssertEqual(SessionCardSnapshot.Status(metadataValue: "done"), .done)
        XCTAssertEqual(SessionCardSnapshot.Status(metadataValue: "offline"), .exited)
        XCTAssertNil(SessionCardSnapshot.Status(metadataValue: "unknown-status"))
    }

    func testStatusParsingUsesAgentStatusIconsForLocalizedValues() {
        let entry = SidebarStatusEntry(
            key: "codex",
            value: "Codex が入力を必要としています",
            icon: "bell.fill"
        )

        XCTAssertEqual(SessionCardSnapshot.Status(sidebarEntry: entry), .needsInput)
    }

    func testStatusParsingKeepsPlainCheckmarkCompletionInFinishedState() {
        let entry = SidebarStatusEntry(
            key: "session",
            value: "Done",
            icon: "checkmark"
        )

        let status = SessionCardSnapshot.Status(sidebarEntry: entry)
        XCTAssertEqual(status, .done)
        XCTAssertEqual(SessionCardSnapshot.Group.resolve(status: .done, isPinned: false), .finished)
    }

    func testStatusGroupMappingUsesPinnedOverrideAndCanonicalStatus() {
        XCTAssertEqual(SessionCardSnapshot.Group.resolve(status: .working, isPinned: true), .pinned)
        XCTAssertEqual(SessionCardSnapshot.Group.resolve(status: .ready, isPinned: false), .needsAttention)
        XCTAssertEqual(SessionCardSnapshot.Group.resolve(status: .needsInput, isPinned: false), .needsAttention)
        XCTAssertEqual(SessionCardSnapshot.Group.resolve(status: .working, isPinned: false), .running)
        XCTAssertEqual(SessionCardSnapshot.Group.resolve(status: .done, isPinned: false), .finished)
        XCTAssertEqual(SessionCardSnapshot.Group.resolve(status: .exited, isPinned: false), .finished)
    }

    func testStatusGroupsHaveRequiredDisplayOrder() {
        XCTAssertEqual(SessionCardSnapshot.Group.allCases, [.pinned, .needsAttention, .running, .finished])
    }

    @MainActor
    func testStatusResolverUsesReadyMetadataAndNeedsInputPrecedence() throws {
        let manager = TabManager()
        let workspace = try XCTUnwrap(manager.tabs.first)
        let panelId = try XCTUnwrap(workspace.focusedPanelId)
        workspace.statusEntries["agent"] = SidebarStatusEntry(key: "agent", value: "Ready")

        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .ready)

        workspace.setAgentLifecycle(key: "codex", panelId: panelId, lifecycle: .running)
        workspace.setAgentLifecycle(key: "claude_code", panelId: panelId, lifecycle: .needsInput)

        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .needsInput)

        XCTAssertTrue(workspace.clearAgentLifecycle(key: "claude_code", panelId: panelId))
        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .working)
    }

    @MainActor
    func testStatusResolverTreatsUnclassifiedIdleWorkspaceAsDone() throws {
        let manager = TabManager()
        let workspace = try XCTUnwrap(manager.tabs.first)

        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .done)
    }

    @MainActor
    func testStatusResolverTracksAgentLifecycleUntilItFinishes() throws {
        let manager = TabManager()
        let workspace = try XCTUnwrap(manager.tabs.first)
        let panelId = try XCTUnwrap(workspace.focusedPanelId)

        workspace.setAgentLifecycle(key: "codex", panelId: panelId, lifecycle: .idle)
        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .ready)

        workspace.setAgentLifecycle(key: "codex", panelId: panelId, lifecycle: .running)
        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .working)

        workspace.setAgentLifecycle(key: "codex", panelId: panelId, lifecycle: .needsInput)
        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .needsInput)

        XCTAssertTrue(workspace.clearAgentLifecycle(key: "codex", panelId: panelId))
        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .done)
    }

    @MainActor
    func testStatusResolverKeepsPersistentRemoteSessionLiveAcrossTransportExit() throws {
        let manager = TabManager()
        let workspace = try XCTUnwrap(manager.tabs.first)
        let panelId = try XCTUnwrap(workspace.focusedPanelId)
        workspace.configureRemoteConnection(
            WorkspaceRemoteConfiguration(
                destination: "devbox",
                port: nil,
                identityFile: nil,
                sshOptions: [],
                localProxyPort: nil,
                relayPort: nil,
                relayID: nil,
                relayToken: nil,
                localSocketPath: nil,
                terminalStartupCommand: "ssh -tt devbox",
                preserveAfterTerminalExit: true
            ),
            autoConnect: false
        )

        XCTAssertEqual(workspace.remoteConnectionState, .disconnected)
        XCTAssertTrue(workspace.hasActiveRemoteTerminalSessions)
        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .ready)

        workspace.statusEntries["session"] = SidebarStatusEntry(
            key: "session",
            value: "Working",
            icon: "bolt.fill"
        )
        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .working)

        workspace.statusEntries.removeValue(forKey: "session")
        workspace.untrackRemoteTerminalSurface(panelId)
        XCTAssertEqual(SessionCardSnapshot.Status.resolve(workspace: workspace), .exited)
    }

    func testDiffParsingNormalizesSignedCounts() {
        XCTAssertEqual(SessionCardSnapshot.Diff.parseCount("+318"), 318)
        XCTAssertEqual(SessionCardSnapshot.Diff.parseCount("-92"), 92)
        XCTAssertEqual(SessionCardSnapshot.Diff.parseCount(""), 0)
        XCTAssertEqual(SessionCardSnapshot.Diff(added: -1, deleted: -2), SessionCardSnapshot.Diff(added: 1, deleted: 2))
    }

    func testWorkspaceNumberClampsToSupportedBadgeRange() {
        XCTAssertEqual(Self.snapshot(workspaceNumber: 0).workspaceNumber, 1)
        XCTAssertEqual(Self.snapshot(workspaceNumber: 7).workspaceNumber, 7)
        XCTAssertEqual(Self.snapshot(workspaceNumber: 42).workspaceNumber, 10)
    }

    func testDefaultBadgeUsesClampedWorkspaceNumber() {
        XCTAssertEqual(Self.snapshot(workspaceNumber: 42).badge, .indexedWorktree(10))
    }

    func testExplicitUnindexedBadgeIsPreserved() {
        let snapshot = SessionCardSnapshot(
            workspaceNumber: 7,
            name: "Card",
            colorHex: "#4493F8",
            host: .devbox,
            branchName: "main",
            modelName: "gpt-5",
            mode: .plan,
            status: .working,
            diff: SessionCardSnapshot.Diff(added: 1, deleted: 2),
            badge: .unindexedHost(.devbox)
        )

        XCTAssertEqual(snapshot.badge, .unindexedHost(.devbox))
    }

    func testIndexedWorktreeParsingRecognizesWorkspaceLaunchers() {
        XCTAssertEqual(SessionCardSnapshot.indexedWorktreeNumber(in: "/projects/service-wk3"), 3)
        XCTAssertEqual(SessionCardSnapshot.indexedWorktreeNumber(in: "~/ws-wk3.sh"), 3)
        XCTAssertEqual(SessionCardSnapshot.indexedWorktreeNumber(in: "[wk10] local"), 10)
        XCTAssertEqual(SessionCardSnapshot.indexedWorktreeNumber(in: "/tmp/wk7"), 7)
        XCTAssertEqual(SessionCardSnapshot.indexedWorktreeNumber(in: "7️⃣ Cmux Test Six"), 7)
        XCTAssertNil(SessionCardSnapshot.indexedWorktreeNumber(in: "/tmp/wk7-extra"))
    }

    private static func snapshot(workspaceNumber: Int) -> SessionCardSnapshot {
        SessionCardSnapshot(
            workspaceNumber: workspaceNumber,
            name: "Card",
            colorHex: "#4493F8",
            host: .laptop,
            branchName: "main",
            modelName: "gpt-5",
            mode: .plan,
            status: .working,
            diff: SessionCardSnapshot.Diff(added: 1, deleted: 2)
        )
    }
}

final class SidebarSelectedWorkspaceScrollPolicyTests: XCTestCase {
    func testSkipsScrollWhenSelectedWorkspaceIdIsNil() {
        XCTAssertFalse(
            SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
                selectedWorkspaceId: nil as String?,
                oldWorkspaceIds: ["a"],
                newWorkspaceIds: ["a"]
            )
        )
    }

    func testRequestsScrollWhenSelectedWorkspaceFirstAppears() {
        XCTAssertTrue(
            SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
                selectedWorkspaceId: "b",
                oldWorkspaceIds: ["a"],
                newWorkspaceIds: ["a", "b"]
            )
        )
    }

    func testRequestsScrollWhenSelectedWorkspaceMovesToTop() {
        XCTAssertTrue(
            SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
                selectedWorkspaceId: "c",
                oldWorkspaceIds: ["a", "b", "c"],
                newWorkspaceIds: ["c", "a", "b"]
            )
        )
    }

    func testRequestsScrollWhenAnotherReorderShiftsSelectedWorkspaceIndex() {
        XCTAssertTrue(
            SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
                selectedWorkspaceId: "b",
                oldWorkspaceIds: ["a", "b", "c"],
                newWorkspaceIds: ["c", "a", "b"]
            )
        )
    }

    func testSkipsScrollWhenReorderLeavesSelectedWorkspaceIndexUnchanged() {
        XCTAssertFalse(
            SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
                selectedWorkspaceId: "a",
                oldWorkspaceIds: ["a", "b", "c"],
                newWorkspaceIds: ["a", "c", "b"]
            )
        )
    }

    func testSkipsScrollWhenSelectedWorkspaceIsMissing() {
        XCTAssertFalse(
            SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
                selectedWorkspaceId: "b",
                oldWorkspaceIds: ["a", "b"],
                newWorkspaceIds: ["a", "c"]
            )
        )
    }
}

final class SidebarWorkspaceRowInteractionStateTests: XCTestCase {
    func testHoverRevealIsIndependentFromStaleContextMenuVisibility() {
        var state = SidebarWorkspaceRowInteractionState()

        state.contextMenuDidAppear()
        state.contextMenuTrackingDidEnd()
        state.setPointerHovering(true)

        XCTAssertTrue(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            ),
            "A stale SwiftUI context-menu lifecycle flag must not permanently suppress hover-only close affordances after AppKit menu tracking has ended."
        )

        state.setPointerHovering(false)

        XCTAssertFalse(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            ),
            "The stale SwiftUI menu flag must not make the close affordance visible when the pointer is no longer hovering."
        )
    }

    func testContextMenuTrackingBeginHidesExistingCloseButtonBeforeSwiftUIMenuAppears() {
        var state = SidebarWorkspaceRowInteractionState()

        state.setPointerHovering(true)
        XCTAssertTrue(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            )
        )

        state.contextMenuTrackingDidBegin()

        XCTAssertFalse(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            ),
            "Right-click menu tracking must hide an already-visible close affordance even before SwiftUI reports the context menu appearance."
        )
    }

    func testHoverDuringContextMenuTrackingStaysHiddenUntilTrackingEnds() {
        var state = SidebarWorkspaceRowInteractionState()

        state.contextMenuDidAppear()
        state.setPointerHovering(true)

        XCTAssertFalse(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            ),
            "Pointer hover updates observed during context-menu tracking must not reveal the close affordance under the menu."
        )

        state.contextMenuTrackingDidEnd()

        XCTAssertTrue(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            ),
            "Once AppKit menu tracking ends, the last reconciled pointer position may reveal the close affordance even if SwiftUI menu state is stale."
        )
    }

    func testCoordinatorPreservesHoverExitWhileMenuTrackingSuppressesCloseButton() {
        var state = SidebarWorkspaceRowInteractionState()
        let binding = Binding<SidebarWorkspaceRowInteractionState>(
            get: { state },
            set: { state = $0 }
        )
        let coordinator = SidebarWorkspaceRowHoverTracker.Coordinator(
            rowInteractionState: binding
        )

        coordinator.menuTrackingChanged(true)
        coordinator.pointerHoverChanged(true)
        coordinator.pointerHoverChanged(false)
        coordinator.menuTrackingChanged(false)

        XCTAssertFalse(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            ),
            "A pointer exit observed during menu tracking must overwrite any earlier deferred hover enter before the menu dismisses."
        )
    }

    func testMenuTrackingSuppressionOnlyAppliesToPointerMenusInsideRow() {
        XCTAssertTrue(
            SidebarWorkspaceRowMenuTrackingScope.shouldSuppressCloseButton(
                pointerInsideRow: true,
                eventType: .rightMouseDown,
                modifierFlags: []
            )
        )
        XCTAssertTrue(
            SidebarWorkspaceRowMenuTrackingScope.shouldSuppressCloseButton(
                pointerInsideRow: true,
                eventType: .leftMouseDown,
                modifierFlags: .control
            )
        )
        XCTAssertFalse(
            SidebarWorkspaceRowMenuTrackingScope.shouldSuppressCloseButton(
                pointerInsideRow: false,
                eventType: .rightMouseDown,
                modifierFlags: []
            ),
            "A menu opened outside this row must not suppress this row's hover state."
        )
        XCTAssertFalse(
            SidebarWorkspaceRowMenuTrackingScope.shouldSuppressCloseButton(
                pointerInsideRow: true,
                eventType: .keyDown,
                modifierFlags: []
            ),
            "Keyboard-driven or app-level menu tracking must not be treated like this row's pointer context menu."
        )
    }

    func testPointerExitWhileContextMenuIsVisibleStaysHiddenAfterDismissal() {
        var state = SidebarWorkspaceRowInteractionState()

        state.setPointerHovering(true)
        state.contextMenuDidAppear()
        state.setPointerHovering(false)
        state.contextMenuDidDisappear()

        XCTAssertFalse(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            ),
            "Pointer exit remains authoritative even when it is observed during the context-menu lifecycle."
        )
    }

    func testNoHoverDoesNotRevealCloseButtonWhileContextMenuIsVisible() {
        var state = SidebarWorkspaceRowInteractionState()

        state.contextMenuDidAppear()
        state.setPointerHovering(false)

        XCTAssertFalse(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            ),
            "A visible context menu must not make the close affordance visible when the pointer is not hovering."
        )
    }

    func testContextMenuAppearanceHidesExistingCloseButtonUntilPointerIsReconciled() {
        var state = SidebarWorkspaceRowInteractionState()

        state.setPointerHovering(true)
        XCTAssertTrue(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            )
        )

        state.contextMenuDidAppear()

        XCTAssertFalse(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            ),
            "Opening a context menu must clear the row close affordance until tracking reports the pointer is still inside."
        )
    }

    func testContextMenuDismissalCanRevealAfterPointerReconciliation() {
        var state = SidebarWorkspaceRowInteractionState()

        state.setPointerHovering(true)
        state.contextMenuDidAppear()
        state.contextMenuDidDisappear()
        state.setPointerHovering(true)

        XCTAssertTrue(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: false
            ),
            "Closing the context menu may reveal the close affordance again only after pointer tracking reconciles inside the row."
        )
    }

    func testCloseButtonHiddenWhenWorkspaceCannotBeClosed() {
        var state = SidebarWorkspaceRowInteractionState()

        state.setPointerHovering(true)

        XCTAssertFalse(
            state.shouldShowCloseButton(
                canCloseWorkspace: false,
                shortcutHintModeActive: false
            )
        )
    }

    func testCloseButtonHiddenDuringShortcutHintMode() {
        var state = SidebarWorkspaceRowInteractionState()

        state.setPointerHovering(true)

        XCTAssertFalse(
            state.shouldShowCloseButton(
                canCloseWorkspace: true,
                shortcutHintModeActive: true
            )
        )
    }
}
