import Foundation
import Testing
@testable import CmuxControlSocket

@MainActor
@Suite("ControlCommandCoordinator sidebar v1 dispatch")
struct ControlCommandCoordinatorSidebarV1Tests {
    @Test func v2PullRequestReportForwardsExplicitSurfaceMutation() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        let workspaceID = UUID()
        let surfaceID = UUID()

        let result = coordinator.handleSocketWorkerV2(
            ControlRequest(
                id: .int(1),
                method: "surface.report_pull_request",
                params: [
                    "workspace_id": .string(workspaceID.uuidString),
                    "surface_id": .string(surfaceID.uuidString),
                    "number": .int(42),
                    "url": .string("https://github.com/example/project/pull/42"),
                    "state": .string("open"),
                    "branch": .string("feature/session-metadata"),
                ]
            ),
            context: context
        )

        #expect(result == .ok(.object([
            "workspace_id": .string(workspaceID.uuidString),
            "surface_id": .string(surfaceID.uuidString),
            "number": .int(42),
        ])))
        #expect(context.pullRequestUpdateCall?.target.scope == ControlSidebarPanelScope(
            workspaceID: workspaceID,
            panelID: surfaceID
        ))
        #expect(context.pullRequestUpdateCall?.number == 42)
        #expect(context.pullRequestUpdateCall?.statusRawValue == "open")
        #expect(context.pullRequestUpdateCall?.branch == "feature/session-metadata")
    }

    @Test func v2StatusSetForwardsRemoteWorkspaceMutation() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        let workspaceID = UUID()

        let result = coordinator.handleSocketWorkerV2(
            ControlRequest(
                id: .int(1),
                method: "sidebar.set_status",
                params: [
                    "workspace_id": .string(workspaceID.uuidString),
                    "key": .string("agent"),
                    "value": .string("Working"),
                    "icon": .string("bolt.fill"),
                    "color": .string("#4C8DFF"),
                    "priority": .string("90"),
                ]
            ),
            context: context
        )

        #expect(result == .ok(.object([
            "workspace_id": .string(workspaceID.uuidString),
            "key": .string("agent"),
        ])))
        #expect(context.statusUpsertCall?.target == .workspace(workspaceID))
        #expect(context.statusUpsertCall?.key == "agent")
        #expect(context.statusUpsertCall?.value == "Working")
        #expect(context.statusUpsertCall?.icon == "bolt.fill")
        #expect(context.statusUpsertCall?.color == "#4C8DFF")
        #expect(context.statusUpsertCall?.priority == 90)
        #expect(context.statusUpsertCall?.format == .plain)
        #expect(context.statusUpsertCall?.panelID == nil)
        #expect(context.statusUpsertCall?.pid == nil)
    }

    @Test func v2StatusClearForwardsRemoteWorkspaceMutation() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        let workspaceID = UUID()

        let result = coordinator.handleSocketWorkerV2(
            ControlRequest(
                id: .int(2),
                method: "sidebar.clear_status",
                params: [
                    "workspace_id": .string(workspaceID.uuidString),
                    "key": .string("agent"),
                ]
            ),
            context: context
        )

        #expect(result == .ok(.object([
            "workspace_id": .string(workspaceID.uuidString),
            "key": .string("agent"),
        ])))
        #expect(context.statusClearCall?.target == .workspace(workspaceID))
        #expect(context.statusClearCall?.key == "agent")
        #expect(context.statusClearCall?.panelID == nil)
    }

    @Test func v2StatusSetRejectsMalformedWorkspaceBeforeMutation() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)

        let result = coordinator.handleSocketWorkerV2(
            ControlRequest(
                id: .int(3),
                method: "sidebar.set_status",
                params: [
                    "workspace_id": .string("not-a-workspace"),
                    "key": .string("agent"),
                    "value": .string("Working"),
                ]
            ),
            context: context
        )

        guard case .err(let code, _, _) = result else {
            Issue.record("Expected invalid_params error")
            return
        }
        #expect(code == "invalid_params")
        #expect(context.statusUpsertCall == nil)
    }

    @Test func v2StatusSetResolvesWorkspaceRefBeforeMutation() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        let workspaceID = UUID()
        let workspaceRef = coordinator.handles.ensureRef(kind: .workspace, uuid: workspaceID)

        let result = coordinator.handleSocketWorkerV2(
            ControlRequest(
                id: .int(4),
                method: "sidebar.set_status",
                params: [
                    "workspace_id": .string(workspaceRef),
                    "key": .string("agent"),
                    "value": .string("Working"),
                    "icon": .string("bolt.fill"),
                    "color": .string("#4C8DFF"),
                    "priority": .string("90"),
                ]
            ),
            context: context
        )

        #expect(result == .ok(.object([
            "workspace_id": .string(workspaceID.uuidString),
            "key": .string("agent"),
        ])))
        #expect(context.statusUpsertCall?.target == .workspace(workspaceID))
        #expect(context.statusUpsertCall?.key == "agent")
        #expect(context.statusUpsertCall?.value == "Working")
    }

    @Test func agentPIDClearForwardsOwnedKeyRequirement() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        let workspaceID = UUID()
        let panelID = UUID()

        let response = coordinator.handleSidebarV1(
            command: "clear_agent_pid",
            args: "omp.stale --tab=\(workspaceID.uuidString) --panel=\(panelID.uuidString) "
                + "--clear-status --require-owned-key"
        )

        #expect(response == "OK")
        #expect(context.agentPIDClearCall?.target == .workspace(workspaceID))
        #expect(context.agentPIDClearCall?.key == "omp.stale")
        #expect(context.agentPIDClearCall?.panelID == panelID)
        #expect(context.agentPIDClearCall?.clearStatus == true)
        #expect(context.agentPIDClearCall?.requireOwnedKey == true)
    }

    @Test func statusClearForwardsPanelScope() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        let workspaceID = UUID()
        let panelID = UUID()

        let response = coordinator.handleSidebarV1(
            command: "clear_status",
            args: "omp --tab=\(workspaceID.uuidString) --panel=\(panelID.uuidString)"
        )

        #expect(response == "OK")
        #expect(context.statusClearCall?.target == .workspace(workspaceID))
        #expect(context.statusClearCall?.key == "omp")
        #expect(context.statusClearCall?.panelID == panelID)
    }

    @Test func statusUpsertForwardsAgentWorkState() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        let workspaceID = UUID()

        let response = coordinator.handleSidebarV1(
            command: "set_status",
            args: "claude_code Running subagents --icon=bolt.fill --work=SUBAGENTS --tab=\(workspaceID.uuidString)"
        )

        #expect(response == "OK")
        #expect(context.statusUpsertCall?.key == "claude_code")
        #expect(context.statusUpsertCall?.value == "Running subagents")
        #expect(context.statusUpsertCall?.workState == .subagents)
    }

    /// Every existing reporter omits `--work`, and those rows must keep
    /// resolving the way they did before the option existed.
    @Test func statusUpsertWithoutWorkOptionForwardsNoWorkState() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)

        let response = coordinator.handleSidebarV1(
            command: "set_status",
            args: "claude_code Running --icon=bolt.fill --tab=\(UUID().uuidString)"
        )

        #expect(response == "OK")
        #expect(context.statusUpsertCall?.workState == nil)
    }

    @Test func statusUpsertRejectsUnknownWorkStateBeforeMutation() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)

        let response = coordinator.handleSidebarV1(
            command: "set_status",
            args: "claude_code Thinking --work=thinking --tab=\(UUID().uuidString)"
        )

        #expect(response?.hasPrefix("ERROR: Invalid work state 'thinking'") == true,
                "An unknown work state must be named in the error; saw \(response ?? "nil")")
        #expect(context.statusUpsertCall == nil)
    }

    /// The work state drives a glyph with no text of its own, so the
    /// `list_status` / `sidebar_state` line has to carry it: it is the only
    /// way a test or a user can see which state a row is actually in.
    @Test func statusListingLineCarriesTheWorkState() {
        let coordinator = ControlCommandCoordinator(context: FakeSidebarV1ControlCommandContext())
        let waiting = ControlSidebarStatusEntrySnapshot(
            key: "claude_code",
            value: "Waiting",
            icon: "hourglass",
            color: "#8E8E93",
            urlAbsoluteString: nil,
            priority: 0,
            format: .plain,
            workState: .waiting
        )
        #expect(coordinator.sidebarMetadataLine(waiting)
            == "claude_code=Waiting icon=hourglass color=#8E8E93 work=waiting")

        let plain = ControlSidebarStatusEntrySnapshot(
            key: "deploy",
            value: "staging green",
            icon: nil,
            color: nil,
            urlAbsoluteString: nil,
            priority: 0,
            format: .plain
        )
        #expect(coordinator.sidebarMetadataLine(plain) == "deploy=staging green")
    }

    @Test func workspaceLoadingFailureReasonReturnsErrorLine() {
        let context = FakeSidebarV1ControlCommandContext()
        context.workspaceLoadingResult = ControlSidebarWorkspaceLoadingState(
            before: false,
            after: false,
            failureReason: "Manual workspace loading limit reached"
        )
        let coordinator = ControlCommandCoordinator(context: context)

        let response = coordinator.handleSidebarV1(
            command: "workspace_loading",
            args: "manual on --tab=workspace-1"
        )

        #expect(response == "ERROR: Manual workspace loading limit reached")
        #expect(context.workspaceLoadingCall?.tabArg == "workspace-1")
        #expect(context.workspaceLoadingCall?.key == "manual")
        #expect(context.workspaceLoadingCall?.on == true)
    }

    @Test func workspaceLoadingRejectsExplicitEmptyTabBeforeMutation() {
        let context = FakeSidebarV1ControlCommandContext()
        context.workspaceLoadingResult = ControlSidebarWorkspaceLoadingState(before: false, after: true)
        let coordinator = ControlCommandCoordinator(context: context)

        let blankForms = [
            "manual on --tab",
            "manual on --tab=",
        ]

        for args in blankForms {
            let response = coordinator.handleSidebarV1(
                command: "workspace_loading",
                args: args
            )

            #expect(response == "ERROR: Invalid --tab; expected a workspace id, ref, or index")
            #expect(context.workspaceLoadingCall == nil)
        }
    }

    @Test func shellStateForwardsTerminalLifecycleScope() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        let workspaceID = UUID()
        let panelID = UUID()
        let terminalLifecycleID = UUID()

        let response = coordinator.handleSidebarV1(
            command: "report_shell_state",
            args: "prompt --tab=\(workspaceID.uuidString) "
                + "--panel=\(panelID.uuidString) "
                + "--terminal-lifecycle-id=\(terminalLifecycleID.uuidString)"
        )

        #expect(response == "OK")
        #expect(context.shellStateCall?.scope.workspaceID == workspaceID)
        #expect(context.shellStateCall?.scope.panelID == panelID)
        #expect(
            context.shellStateCall?.scope.terminalLifecycleID
                == terminalLifecycleID
        )
        #expect(context.shellStateCall?.stateRawValue == "promptIdle")
    }

    @Test func shellStateRejectsMalformedTerminalLifecycleScope() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)

        let response = coordinator.handleSidebarV1(
            command: "report_shell_state",
            args: "prompt --tab=\(UUID().uuidString) "
                + "--panel=\(UUID().uuidString) "
                + "--terminal-lifecycle-id=not-a-uuid"
        )

        #expect(response == "ERROR: Terminal session is out of date; restart the shell and try again")
        #expect(context.shellStateCall == nil)
    }

    @Test func shellStateRejectsLifecycleIdentityWithoutCompleteScope() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)

        let response = coordinator.handleSidebarV1(
            command: "report_shell_state",
            args: "prompt --tab=\(UUID().uuidString) "
                + "--terminal-lifecycle-id=\(UUID().uuidString)"
        )

        #expect(response == "ERROR: Terminal session is out of date; restart the shell and try again")
        #expect(context.shellStateCall == nil)
    }

    @Test func workspacePullRequestHandoffUsesWorkspaceScope() throws {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        let workspaceID = UUID()
        let url = try #require(URL(string: "https://github.com/manaflow-ai/cmux/pull/12746"))

        let response = coordinator.handleSidebarV1(
            command: "report_workspace_pr",
            args: "12746 \"\(url.absoluteString)\" --label=PR --state=merged "
                + "--branch=feature/pr --tab=\(workspaceID.uuidString)"
        )

        #expect(response == "OK")
        #expect(context.manualPullRequestCall?.tabArg == workspaceID.uuidString)
        #expect(context.manualPullRequestCall?.number == 12746)
        #expect(context.manualPullRequestCall?.label == "PR")
        #expect(context.manualPullRequestCall?.url == url)
        #expect(context.manualPullRequestCall?.state == "merged")
        #expect(context.manualPullRequestCall?.branch == "feature/pr")
    }

    @Test(arguments: ["report_workspace_pr", "clear_workspace_pr"])
    func workspacePullRequestRejectsMissingWorkspace(command: String) {
        let context = FakeSidebarV1ControlCommandContext()
        context.manualPullRequestAvailable = false
        let coordinator = ControlCommandCoordinator(context: context)
        let target = "--tab=\(UUID().uuidString)"
        let args = command == "report_workspace_pr"
            ? "123 https://github.com/owner/repo/pull/123 \(target)"
            : target
        #expect(coordinator.handleSidebarV1(command: command, args: args)?.hasPrefix("ERROR") == true)
        #expect(context.manualPullRequestCall == nil)
        #expect(context.manualPullRequestClearTab == nil)
    }

    @Test func workspacePullRequestClearUsesWorkspaceScope() {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        let workspaceID = UUID()

        let response = coordinator.handleSidebarV1(
            command: "clear_workspace_pr",
            args: "--tab=\(workspaceID.uuidString)"
        )

        #expect(response == "OK")
        #expect(context.manualPullRequestClearTab == workspaceID.uuidString)
    }
    @Test(arguments: [
        "123 https://github.com/owner/repo/pull/123",
        "123 https://github.com/owner/repo/pull/123 --tab=",
        "123 javascript:alert(1) --tab=11111111-1111-1111-1111-111111111111",
        "123 https://github.com/owner/repo/pull/124 --tab=11111111-1111-1111-1111-111111111111",
        "123 https://github.com/owner/repo/pull/123 --tab=11111111-1111-1111-1111-111111111111 --state=invalid"
    ])
    func workspacePullRequestRejectsInvalidHandoffBeforeMutation(args: String) {
        let context = FakeSidebarV1ControlCommandContext()
        let coordinator = ControlCommandCoordinator(context: context)
        #expect(coordinator.handleSidebarV1(command: "report_workspace_pr", args: args)?.hasPrefix("ERROR") == true)
        #expect(context.manualPullRequestCall == nil)
    }

}
