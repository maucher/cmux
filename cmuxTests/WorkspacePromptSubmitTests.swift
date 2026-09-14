import Foundation
import Testing
import CMUXAgentLaunch

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite(.serialized)
struct WorkspacePromptSubmitTests {
    @Test func forwardedSocketUsesHostBuildIdentityDespiteStaleEnvironment() {
        let environment = PromptLauncherEnvironment(
            inherited: [
                "CMUX_SOCKET_PATH": "/tmp/cmux-debug-old.sock",
                "CMUX_SOCKET": "/tmp/cmux-debug-old.sock",
                "CMUX_BUNDLED_CLI_PATH": "/old/cmux",
                "CMUX_BUNDLE_ID": "old.bundle",
                "CMUX_TAG": "old",
                "PATH": "/usr/bin"
            ],
            bundledCLIPath: "/current/cmux",
            bundleIdentifier: "current.bundle",
            bundleTag: "current"
        ).merging([
            "CMUX_BUNDLED_CLI_PATH": "/configured/old/cmux",
            "CMUX_SOCKET": "/tmp/configured-old.sock",
            "CUSTOM_SETTING": "preserved"
        ], forwardedSocketPath: "/tmp/cmux-debug-current.sock")

        #expect(environment["CMUX_SOCKET_PATH"] == "/tmp/cmux-debug-current.sock")
        #expect(environment["CMUX_SOCKET"] == nil)
        #expect(environment["CMUX_BUNDLED_CLI_PATH"] == "/current/cmux")
        #expect(environment["CMUX_BUNDLE_ID"] == "current.bundle")
        #expect(environment["CMUX_TAG"] == "current")
        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment["CUSTOM_SETTING"] == "preserved")
    }

    @Test func disablingSocketForwardingPreservesConfiguredEnvironment() {
        let environment = PromptLauncherEnvironment(
            inherited: ["PATH": "/usr/bin", "CUSTOM_SETTING": "old"],
            bundledCLIPath: "/current/cmux",
            bundleIdentifier: "current.bundle",
            bundleTag: "current"
        ).merging(["CUSTOM_SETTING": "configured"], forwardedSocketPath: nil)

        #expect(environment == ["PATH": "/usr/bin", "CUSTOM_SETTING": "configured"])
    }

    @Test func repositorySelectionPreservesManualEnvironmentAndAgent() {
        let model = PromptLauncherModel(commandRunner: PromptLauncherCommandRunnerSpy())
        let config = promptLauncherSelectionConfig()
        model.configure(config)
        model.selectedTarget = "local"
        model.selectedProvider = "codex"
        model.promptText = "Keep my draft"

        for repository in ["backend", "tools", "backend"] {
            model.selectRepository(repository)
            model.configure(config)
            #expect(model.selectedRepository == repository)
            #expect(model.selectedTarget == "local")
            #expect(model.selectedProvider == "codex")
            #expect(model.promptText == "Keep my draft")
        }
    }

    @Test func launchUsesManualEnvironmentAgentAndRepository() {
        let model = PromptLauncherModel(commandRunner: PromptLauncherCommandRunnerSpy())
        let config = promptLauncherSelectionConfig()
        model.configure(config)
        model.selectedTarget = "local"
        model.selectedProvider = "codex"
        model.selectRepository("tools")
        model.promptText = "Use my selections"

        model.launch(
            config: config,
            tabManager: TabManager(),
            configSourcePath: "/tmp/cmux.json",
            globalConfigPath: "/tmp/cmux.json"
        )

        #expect(model.jobs.count == 1)
        #expect(model.jobs.first?.targetID == "local")
        #expect(model.jobs.first?.providerID == "codex")
        #expect(model.jobs.first?.repositoryID == "tools")
    }

    @Test func unsupportedEnvironmentIsPreservedWithoutLaunching() {
        let model = PromptLauncherModel(commandRunner: PromptLauncherCommandRunnerSpy())
        let config = promptLauncherSelectionConfig()
        model.configure(config)
        model.selectedProvider = "codex"
        model.selectRepository("tools")
        model.promptText = "Keep my draft"
        model.launch(
            config: config,
            tabManager: TabManager(),
            configSourcePath: "/tmp/cmux.json",
            globalConfigPath: "/tmp/cmux.json"
        )

        #expect(model.selectedTarget == "auto")
        #expect(model.selectedProvider == "codex")
        #expect(model.selectedRepository == "tools")
        #expect(model.promptText == "Keep my draft")
        #expect(model.jobs.isEmpty)
        #expect(!model.isTargetSupported(config))

        model.selectedTarget = "local"
        #expect(model.isTargetSupported(config))
        #expect(model.selectedRepository == "tools")
        #expect(model.selectedProvider == "codex")
    }

    @Test func autoResetRestoresDestinationAndPreservesAgentAndDraft() {
        let model = PromptLauncherModel(commandRunner: PromptLauncherCommandRunnerSpy())
        let config = promptLauncherSelectionConfig()
        model.configure(config)
        model.selectedTarget = "local"
        model.selectedProvider = "codex"
        model.selectRepository("tools")
        model.promptText = "Keep my draft"

        model.resetDestination(config)

        #expect(model.selectedTarget == "auto")
        #expect(model.selectedRepository == "backend")
        #expect(model.selectedProvider == "codex")
        #expect(model.promptText == "Keep my draft")
    }

    @Test func configurationRefreshOnlyReplacesChoicesRemovedFromConfiguration() {
        let model = PromptLauncherModel(commandRunner: PromptLauncherCommandRunnerSpy())
        var config = promptLauncherSelectionConfig()
        model.configure(config)
        #expect(model.selectedRepository == "backend")
        #expect(model.selectedTarget == "auto")
        #expect(model.selectedProvider == "claude")
        model.selectedTarget = "local"
        model.selectedProvider = "codex"
        model.selectRepository("tools")

        config.repositories.removeAll { $0.id == "tools" }
        model.configure(config)
        #expect(model.selectedRepository == "backend")
        #expect(model.selectedTarget == "local")
        #expect(model.selectedProvider == "codex")
    }

    private func promptLauncherSelectionConfig() -> CmuxPromptLauncherDefinition {
        CmuxPromptLauncherDefinition(
            command: "echo {{target.id}} {{provider.id}} {{repository.id}} {{prompt}}",
            targets: [.init(id: "auto"), .init(id: "local"), .init(id: "devbox")],
            providers: [.init(id: "claude"), .init(id: "codex")],
            repositories: [
                .init(id: "backend", defaultTarget: "auto"),
                .init(id: "tools", allowedTargets: ["local", "devbox"], defaultTarget: "devbox")
            ],
            defaultTarget: "auto",
            defaultProvider: "claude",
            defaultRepository: "backend",
            forwardCmuxSocket: false
        )
    }

    @Test func promptLauncherProcessRunnerStreamsOutputAndExitStatus() async {
        let runner = PromptLauncherProcessRunner()
        let stream = await runner.events(
            shellCommand: "printf 'first\\nsecond\\n'; exit 3",
            environment: [:],
            forwardedSocketPath: nil
        )
        var events: [PromptLauncherCommandEvent] = []
        for await event in stream {
            events.append(event)
        }

        #expect(events.contains(.output("first")))
        #expect(events.contains(.output("second")))
        #expect(events.last == .finished(exitStatus: 3))
    }

    @Test func promptLauncherAcceptsConcurrentJobsWithoutBlockingTheComposer() async throws {
        let runner = PromptLauncherCommandRunnerSpy()
        var requests = runner.requests.makeAsyncIterator()
        let model = PromptLauncherModel(commandRunner: runner)
        let manager = TabManager()
        let config = promptLauncherQueueConfig()

        model.promptText = "First prompt"
        model.launch(
            config: config,
            tabManager: manager,
            configSourcePath: "/tmp/cmux.json",
            globalConfigPath: "/tmp/cmux.json"
        )
        #expect(model.promptText.isEmpty)

        model.promptText = "Second prompt"
        model.launch(
            config: config,
            tabManager: manager,
            configSourcePath: "/tmp/cmux.json",
            globalConfigPath: "/tmp/cmux.json"
        )
        #expect(model.promptText.isEmpty)
        #expect(model.visibleJobs.map(\.prompt) == ["First prompt", "Second prompt"])

        let firstRequest = try #require(await requests.next())
        let secondRequest = try #require(await requests.next())
        #expect(firstRequest.shellCommand.contains("'First prompt'"))
        #expect(secondRequest.shellCommand.contains("'Second prompt'"))
        #expect(firstRequest.id != secondRequest.id)
    }

    @Test func promptLauncherMetadataHandsTemporaryJobToWorkspace() async throws {
        let runner = PromptLauncherCommandRunnerSpy()
        var requests = runner.requests.makeAsyncIterator()
        let model = PromptLauncherModel(commandRunner: runner)
        let manager = TabManager()
        let workspace = manager.tabs[0]
        let workspaceRef = try #require(
            TerminalController.shared.v2Ref(kind: .workspace, uuid: workspace.id) as? String
        )
        let config = promptLauncherQueueConfig()

        model.promptText = "Attach me"
        model.launch(
            config: config,
            tabManager: manager,
            configSourcePath: "/tmp/cmux.json",
            globalConfigPath: "/tmp/cmux.json"
        )
        let request = try #require(await requests.next())
        await runner.emit(
            .output(
                "CMUX_WORKSPACE_JSON:{\"workspace\":\"\(workspaceRef)\",\"title\":\"[wk4] Attached\",\"color\":\"#3b82f6\",\"slot\":\"wk4\"}"
            ),
            for: request.id
        )
        await waitUntil { workspace.customTitle == "[wk4] Attached" }

        #expect(model.visibleJobs.isEmpty)
        #expect(workspace.customTitle == "[wk4] Attached")
        #expect(workspace.customColor?.lowercased() == "#3b82f6")
        #expect(workspace.promptLauncherSlot == "wk4")

        await runner.emit(.finished(exitStatus: 1), for: request.id)
        await waitUntil { model.jobs.isEmpty }
        #expect(
            workspace.statusEntries["workflow"]?.value
                == String(localized: "sidebar.sessionGroup.needsAttention", defaultValue: "Needs Attention")
        )
    }

    @Test func structuredPromptLauncherMetadataKeepsJobVisibleUntilReady() async throws {
        let runner = PromptLauncherCommandRunnerSpy()
        var requests = runner.requests.makeAsyncIterator()
        let model = PromptLauncherModel(commandRunner: runner)
        let manager = TabManager()
        let workspace = manager.tabs[0]
        let workspaceRef = try #require(
            TerminalController.shared.v2Ref(kind: .workspace, uuid: workspace.id) as? String
        )
        let config = promptLauncherQueueConfig()

        model.promptText = "Initialize completely"
        model.launch(
            config: config,
            tabManager: manager,
            configSourcePath: "/tmp/cmux.json",
            globalConfigPath: "/tmp/cmux.json"
        )
        let request = try #require(await requests.next())

        await runner.emit(
            .output(
                "CMUX_WORKSPACE_JSON:{\"workspace\":\"\(workspaceRef)\",\"title\":\"3️⃣ Existing\",\"color\":\"#3b82f6\",\"slot\":\"wk3\",\"phase\":\"attached\"}"
            ),
            for: request.id
        )
        await runner.emit(.output(##"CMUX_WORKSPACE_JSON:{"progress":"[5/6] Starting agent"}"##), for: request.id)
        await waitUntil { model.jobs.first?.latestLine == "[5/6] Starting agent" }
        await runner.emit(.output("/tmp/private-launch-script.sh --internal-argument"), for: request.id)
        await waitUntil { model.jobs.first?.lastOutput == "/tmp/private-launch-script.sh --internal-argument" }
        #expect(model.jobs.first?.displayTitle == "3️⃣ Existing")
        #expect(model.jobs.first?.latestLine == "[5/6] Starting agent")
        #expect(workspace.statusEntries["launcher.initialization"]?.value == "[5/6] Starting agent")

        #expect(model.visibleJobs.map(\.prompt) == ["Initialize completely"])
        #expect(model.jobs.count == 1)

        await runner.emit(
            .output(
                "CMUX_WORKSPACE_JSON:{\"workspace\":\"\(workspaceRef)\",\"title\":\"3️⃣ Existing\",\"color\":\"#3b82f6\",\"slot\":\"wk3\",\"phase\":\"ready\"}"
            ),
            for: request.id
        )
        await waitUntil { model.jobs.isEmpty }

        #expect(model.visibleJobs.isEmpty)
        #expect(model.jobs.isEmpty)
        #expect(workspace.statusEntries["launcher.initialization"] == nil)
    }

    @Test func promptLauncherCloseJobsRemainVisibleOnFailureAndCanRetry() async throws {
        let runner = PromptLauncherCommandRunnerSpy()
        var requests = runner.requests.makeAsyncIterator()
        let model = PromptLauncherModel(commandRunner: runner)

        model.enqueueClose(
            workspaceName: "[wk2] Cleanup",
            shellCommand: "workspace-reset slot-2",
            environment: [:],
            forwardedSocketPath: "/tmp/cmux.sock"
        )
        let firstRequest = try #require(await requests.next())
        #expect(model.closeJobs.count == 1)
        #expect(model.closeJobs[0].state == .running)

        await runner.emit(.output("reset failed"), for: firstRequest.id)
        await runner.emit(.finished(exitStatus: 1), for: firstRequest.id)
        await waitUntil { model.closeJobs.first?.state == .failed }
        let failedJob = try #require(model.closeJobs.first)
        #expect(failedJob.state == .failed)
        #expect(failedJob.latestLine == "reset failed")

        model.retry(failedJob)
        let retryRequest = try #require(await requests.next())
        #expect(retryRequest.id != firstRequest.id)
        #expect(model.closeJobs.first?.state == .running)

        await runner.emit(.finished(exitStatus: 0), for: retryRequest.id)
        await waitUntil { model.closeJobs.isEmpty }
        #expect(model.closeJobs.isEmpty)
    }

    @Test func promptLauncherTemplateRendersConfiguredCommandVariants() {
        let config = CmuxPromptLauncherDefinition(
            command: "workspace-launch {{provider.args}} {{target.args}} {{prompt}}",
            targets: [
                CmuxPromptLauncherChoice(id: "auto", args: []),
                CmuxPromptLauncherChoice(id: "local", args: ["local"]),
                CmuxPromptLauncherChoice(id: "remote-1", args: ["remote-1"]),
            ],
            providers: [
                CmuxPromptLauncherChoice(id: "claude", args: []),
                CmuxPromptLauncherChoice(id: "cursor", args: ["cursor"]),
                CmuxPromptLauncherChoice(id: "codex", args: ["codex"]),
            ]
        )

        #expect(
            SidebarPromptLauncherTemplateRenderer.renderCommand(
                config: config,
                targetID: "auto",
                providerID: "claude",
                prompt: "Default provider"
            ) == "workspace-launch   'Default provider'"
        )
        #expect(
            SidebarPromptLauncherTemplateRenderer.renderCommand(
                config: config,
                targetID: "local",
                providerID: "cursor",
                prompt: "Use Cursor"
            ) == "workspace-launch 'cursor' 'local' 'Use Cursor'"
        )
        #expect(
            SidebarPromptLauncherTemplateRenderer.renderCommand(
                config: config,
                targetID: "remote-1",
                providerID: "codex",
                prompt: "Add Codex's mode"
            ) == "workspace-launch 'codex' 'remote-1' 'Add Codex'\\''s mode'"
        )
    }

    private func promptLauncherQueueConfig() -> CmuxPromptLauncherDefinition {
        CmuxPromptLauncherDefinition(
            command: "workspace-launch {{provider.args}} {{target.args}} {{prompt}}",
            targets: [CmuxPromptLauncherChoice(id: "auto")],
            providers: [CmuxPromptLauncherChoice(id: "claude")],
            defaultTarget: "auto",
            defaultProvider: "claude",
            metadataPrefix: "CMUX_WORKSPACE_JSON:"
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    @Test func promptLauncherRendersConfiguredRepositoryAndFiltersTargets() {
        let config = CmuxPromptLauncherDefinition(
            command: "workspace-launch --repo {{repository.args}} {{target.args}} {{prompt}}",
            targets: [
                CmuxPromptLauncherChoice(id: "auto"),
                CmuxPromptLauncherChoice(id: "local", args: ["local"]),
                CmuxPromptLauncherChoice(id: "devbox", args: ["devbox"]),
            ],
            providers: [CmuxPromptLauncherChoice(id: "claude")],
            repositories: [
                CmuxPromptLauncherChoice(
                    id: "service",
                    args: ["projects/service"],
                    allowedTargets: ["auto", "local", "devbox"],
                    defaultTarget: "auto"
                ),
                CmuxPromptLauncherChoice(
                    id: "docs",
                    title: "Documentation",
                    args: ["projects/docs"],
                    allowedTargets: ["local", "devbox"],
                    defaultTarget: "devbox"
                ),
            ],
            defaultTarget: "auto",
            defaultRepository: "service"
        )

        #expect(config.selectedDefaultRepositoryID == "service")
        #expect(config.targets(forRepositoryID: "service").map(\.id) == ["auto", "local", "devbox"])
        #expect(config.targets(forRepositoryID: "docs").map(\.id) == ["local", "devbox"])
        #expect(config.selectedDefaultTargetID(forRepositoryID: "service") == "auto")
        #expect(config.selectedDefaultTargetID(forRepositoryID: "docs") == "devbox")
        #expect(
            SidebarPromptLauncherTemplateRenderer.renderCommand(
                config: config,
                targetID: "devbox",
                providerID: "claude",
                repositoryID: "docs",
                prompt: "Update the guide"
            ) == "workspace-launch --repo 'projects/docs' 'devbox' 'Update the guide'"
        )
    }

    @Test func promptLauncherWithoutRepositoriesKeepsExistingTemplateBehavior() {
        let config = CmuxPromptLauncherDefinition(
            command: "workspace-launch {{target.args}} {{prompt}}",
            targets: [CmuxPromptLauncherChoice(id: "auto")],
            providers: [CmuxPromptLauncherChoice(id: "claude")]
        )

        #expect(config.repositories.isEmpty)
        #expect(
            SidebarPromptLauncherTemplateRenderer.renderCommand(
                config: config,
                targetID: "auto",
                providerID: "claude",
                prompt: "Existing config"
            ) == "workspace-launch  'Existing config'"
        )
    }

    @Test func promptLauncherParsesWorkspaceMetadataLine() throws {
        let metadata = try #require(SidebarPromptLauncherTemplateRenderer.metadata(
            from: ##"CMUX_WORKSPACE_JSON:{"workspace":"workspace:3","title":"[wk3] Search","color":"#3b82f6","slot":"wk3"}"##,
            prefix: "CMUX_WORKSPACE_JSON:"
        ))

        #expect(metadata.workspace == "workspace:3")
        #expect(metadata.title == "[wk3] Search")
        #expect(metadata.color == "#3b82f6")
        #expect(metadata.slot == "wk3")
    }

    @Test func promptLauncherCloseHookUsesMetadataOrTitleSlot() {
        let config = CmuxPromptLauncherDefinition(
            command: "workspace-launch {{prompt}}",
            targets: [CmuxPromptLauncherChoice(id: "auto")],
            providers: [CmuxPromptLauncherChoice(id: "claude")],
            closeHook: "workspace-reset {{workspace.slot}}"
        )
        let workspace = Workspace(title: "[wk7] Cleanup")
        #expect(
            SidebarPromptLauncherTemplateRenderer.renderCloseHook(config: config, workspace: workspace)
                == "workspace-reset 'wk7'"
        )

        workspace.promptLauncherSlot = "wk9"
        #expect(
            SidebarPromptLauncherTemplateRenderer.renderCloseHook(config: config, workspace: workspace)
                == "workspace-reset 'wk9'"
        )
    }

    @MainActor
    @Test func promptLauncherRestartHookUsesStableWorkspaceIdentity() throws {
        let config = CmuxPromptLauncherDefinition(
            command: "workspace-launch {{prompt}}",
            targets: [CmuxPromptLauncherChoice(id: "auto")],
            providers: [CmuxPromptLauncherChoice(id: "claude")],
            restartHook: "workspace-restart --workspace {{workspace.id}}"
        )
        let workspace = Workspace()

        #expect(
            SidebarPromptLauncherTemplateRenderer.renderRestartHook(config: config, workspace: workspace)
                == "workspace-restart --workspace '\(workspace.id.uuidString)'"
        )
    }

    @Test func testPromptSubmitRecordsMessageAndMovesWorkspaceToTopWhenIMessageModeEnabled() throws {
        let manager = TabManager()
        let first = manager.tabs[0]
        let second = manager.addWorkspace(select: false, placementOverride: .end)
        let third = manager.addWorkspace(select: false, placementOverride: .end)
        manager.selectWorkspace(second)

        let outcome = try #require(
            manager.handlePromptSubmit(
                workspaceId: third.id,
                message: "  implement this\n\nnow  ",
                iMessageModeEnabled: true
            )
        )

        #expect(outcome.messageRecorded)
        #expect(outcome.reordered)
        #expect(outcome.index == 0)
        #expect(manager.tabs.map(\.id) == [third.id, first.id, second.id])
        #expect(manager.selectedTabId == second.id)
        #expect(third.latestConversationMessage == "implement this now")
        #expect(third.latestSubmittedAt != nil)
    }

    @Test func testPromptSubmitReorderPublishesWorkspaceOrderEvent() throws {
        CmuxEventBus.shared.resetForTesting()
        defer { CmuxEventBus.shared.resetForTesting() }

        let manager = TabManager()
        let first = manager.tabs[0]
        let second = manager.addWorkspace(select: false, placementOverride: .end)
        let third = manager.addWorkspace(select: false, placementOverride: .end)
        CmuxEventBus.shared.resetForTesting()

        let outcome = try #require(
            manager.handlePromptSubmit(
                workspaceId: third.id,
                message: "ship it",
                iMessageModeEnabled: true
            )
        )

        #expect(outcome.reordered)
        let events = CmuxEventBus.shared.retainedSnapshot()
        #expect(events.compactMap { $0["name"] as? String } == ["workspace.prompt.submitted", "workspace.reordered"])
        let reorder = try #require(events.last)
        #expect(reorder["workspace_id"] as? String == third.id.uuidString)
        let payload = try #require(reorder["payload"] as? [String: Any])
        #expect(payload["workspace_ids"] as? [String] == [third.id.uuidString, first.id.uuidString, second.id.uuidString])
        #expect(payload["moved_workspace_ids"] as? [String] == [third.id.uuidString])
    }

    @Test func testPromptSubmitRecordsMessageWithoutReorderingWhenIMessageModeDisabled() throws {
        let manager = TabManager()
        let first = manager.tabs[0]
        let second = manager.addWorkspace(select: false, placementOverride: .end)
        let third = manager.addWorkspace(select: false, placementOverride: .end)

        let outcome = try #require(
            manager.handlePromptSubmit(
                workspaceId: third.id,
                message: "do not show",
                iMessageModeEnabled: false
            )
        )

        #expect(outcome.messageRecorded)
        #expect(!outcome.reordered)
        #expect(outcome.index == 2)
        #expect(manager.tabs.map(\.id) == [first.id, second.id, third.id])
        #expect(third.latestConversationMessage == "do not show")
        #expect(third.latestSubmittedAt != nil)
    }

    @Test func testAssistantFinalMessageRecordsMessageAndMovesWorkspaceToTopWhenIMessageModeEnabled() throws {
        let manager = TabManager()
        let pinned = manager.tabs[0]
        manager.setPinned(pinned, pinned: true)
        let second = manager.addWorkspace(select: false, placementOverride: .end)
        let third = manager.addWorkspace(select: false, placementOverride: .end)
        manager.selectWorkspace(second)

        let outcome = try #require(
            manager.handleAssistantFinalMessage(
                workspaceId: third.id,
                message: "  final\n\nresponse  ",
                iMessageModeEnabled: true
            )
        )

        #expect(outcome.messageRecorded)
        #expect(outcome.reordered)
        #expect(outcome.index == 1)
        #expect(manager.tabs.map(\.id) == [pinned.id, third.id, second.id])
        #expect(manager.selectedTabId == second.id)
        #expect(third.latestConversationMessage == "final response")
    }

    @Test func testAssistantFinalMessageMovesWorkspaceWhenPreviewMatchesExistingMessage() throws {
        let manager = TabManager()
        let pinned = manager.tabs[0]
        manager.setPinned(pinned, pinned: true)
        let second = manager.addWorkspace(select: false, placementOverride: .end)
        let third = manager.addWorkspace(select: false, placementOverride: .end)
        #expect(third.recordConversationMessage("Done."))

        let outcome = try #require(
            manager.handleAssistantFinalMessage(
                workspaceId: third.id,
                message: "Done.",
                iMessageModeEnabled: true
            )
        )

        #expect(!outcome.messageRecorded)
        #expect(outcome.reordered)
        #expect(outcome.index == 1)
        #expect(manager.tabs.map(\.id) == [pinned.id, third.id, second.id])
        #expect(third.latestConversationMessage == "Done.")
    }

    @Test func testBlankAssistantFinalMessageDoesNotMoveWorkspace() throws {
        let manager = TabManager()
        let first = manager.tabs[0]
        let second = manager.addWorkspace(select: false, placementOverride: .end)

        let outcome = try #require(
            manager.handleAssistantFinalMessage(
                workspaceId: second.id,
                message: " \n ",
                iMessageModeEnabled: true
            )
        )

        #expect(!outcome.messageRecorded)
        #expect(!outcome.reordered)
        #expect(outcome.index == 1)
        #expect(manager.tabs.map(\.id) == [first.id, second.id])
        #expect(second.latestConversationMessage == nil)
    }

    @Test func testBlankPromptSubmitDoesNotRecordTimestampOrPublishEvent() throws {
        let manager = TabManager()
        let second = manager.addWorkspace(select: false, placementOverride: .end)
        let sequenceBeforeSubmit = CmuxEventBus.shared.latestSequence

        let outcome = try #require(
            manager.handlePromptSubmit(
                workspaceId: second.id,
                message: " \n ",
                iMessageModeEnabled: false
            )
        )

        #expect(!outcome.messageRecorded)
        #expect(!outcome.reordered)
        #expect(second.latestConversationMessage == nil)
        #expect(second.latestSubmittedAt == nil)
        #expect(CmuxEventBus.shared.latestSequence == sequenceBeforeSubmit)
    }

    @Test func testFeedPromptSubmitEventExtractsToolInputMessage() throws {
        let manager = TabManager()
        let first = manager.tabs[0]
        let second = manager.addWorkspace(select: false, placementOverride: .end)

        let event = WorkstreamEvent(
            sessionId: "opencode-session",
            hookEventName: .userPromptSubmit,
            source: "opencode",
            workspaceId: second.id.uuidString,
            toolInputJSON: #"{"prompt":"  shipped from feed\npath  "}"#,
            context: WorkstreamContext(lastUserMessage: "fallback message")
        )

        let outcome = try #require(
            manager.handlePromptSubmit(
                workspaceId: second.id,
                message: event.submittedPromptMessage,
                iMessageModeEnabled: true
            )
        )

        #expect(outcome.messageRecorded)
        #expect(outcome.reordered)
        #expect(manager.tabs.map(\.id) == [second.id, first.id])
        #expect(second.latestConversationMessage == "shipped from feed path")
    }

    @Test func testFeedPromptSubmitEventFallsBackToContextMessage() {
        let event = WorkstreamEvent(
            sessionId: "agent-session",
            hookEventName: .userPromptSubmit,
            source: "codex",
            workspaceId: UUID().uuidString,
            context: WorkstreamContext(lastUserMessage: "from context")
        )

        #expect(event.submittedPromptMessage == "from context")
    }

    @Test func testFeedPromptSubmitSkipsBlankContextBeforeExtraFields() {
        let event = WorkstreamEvent(
            sessionId: "agent-session",
            hookEventName: .userPromptSubmit,
            source: "codex",
            workspaceId: UUID().uuidString,
            context: WorkstreamContext(lastUserMessage: " \n "),
            extraFieldsJSON: #"{"message":"from extra fields"}"#
        )

        #expect(event.submittedPromptMessage == "from extra fields")
    }

    @Test func testFeedStopEventExtractsAssistantFinalMessageFromContext() {
        let event = WorkstreamEvent(
            sessionId: "agent-session",
            hookEventName: .stop,
            source: "codex",
            workspaceId: UUID().uuidString,
            context: WorkstreamContext(assistantPreamble: "  finished\n\nthis  ")
        )

        #expect(event.assistantFinalMessage == "finished this")
    }

    @Test func testFeedStopEventExtractsAssistantFinalMessageFromExtraFields() {
        let event = WorkstreamEvent(
            sessionId: "agent-session",
            hookEventName: .stop,
            source: "codex",
            workspaceId: UUID().uuidString,
            extraFieldsJSON: #"{"last_assistant_message":"  done\nfrom extra fields  "}"#
        )

        #expect(event.assistantFinalMessage == "done from extra fields")
    }

    @Test func testFeedSubagentStopDoesNotExtractParentAssistantFinalMessage() {
        let event = WorkstreamEvent(
            sessionId: "agent-session",
            hookEventName: .subagentStop,
            source: "codex",
            workspaceId: UUID().uuidString,
            context: WorkstreamContext(assistantPreamble: "subagent finished")
        )

        #expect(event.assistantFinalMessage == nil)
    }

    @Test func testBlankSubmittedMessageDoesNotClearRecordedPreview() {
        let workspace = Workspace()

        #expect(workspace.recordSubmittedMessage("keep this preview"))
        #expect(!workspace.recordSubmittedMessage(" \n "))
        #expect(workspace.latestConversationMessage == "keep this preview")
        #expect(workspace.latestSubmittedAt != nil)
    }

    @Test func testIMessageModeUsesManagedSettingsKey() throws {
        let suiteName = "cmux.iMessageMode.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(IMessageModeSettings.key == "app.iMessageMode")
        #expect(!IMessageModeSettings.isEnabled(defaults: defaults))
        defaults.set(true, forKey: IMessageModeSettings.key)
        #expect(IMessageModeSettings.isEnabled(defaults: defaults))
    }
}

private actor PromptLauncherCommandRunnerSpy: PromptLauncherCommandRunning {
    struct Request: Sendable {
        let id: UUID
        let shellCommand: String
    }

    nonisolated let requests: AsyncStream<Request>
    private let requestContinuation: AsyncStream<Request>.Continuation
    private var eventContinuations: [UUID: AsyncStream<PromptLauncherCommandEvent>.Continuation] = [:]

    init() {
        (requests, requestContinuation) = AsyncStream.makeStream()
    }

    func events(
        shellCommand: String,
        environment _: [String: String],
        forwardedSocketPath _: String?
    ) -> AsyncStream<PromptLauncherCommandEvent> {
        let id = UUID()
        let (events, continuation) = AsyncStream<PromptLauncherCommandEvent>.makeStream()
        eventContinuations[id] = continuation
        requestContinuation.yield(Request(id: id, shellCommand: shellCommand))
        return events
    }

    func emit(_ event: PromptLauncherCommandEvent, for id: UUID) {
        eventContinuations[id]?.yield(event)
        if event.isTerminal {
            eventContinuations.removeValue(forKey: id)?.finish()
        }
    }
}
