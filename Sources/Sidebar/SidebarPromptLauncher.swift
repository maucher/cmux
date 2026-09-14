import AppKit
import CmuxFoundation
import SwiftUI

private struct PromptLauncherArrowCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> ArrowCursorView { ArrowCursorView() }
    func updateNSView(_ nsView: ArrowCursorView, context: Context) {}

    class ArrowCursorView: NSView {
        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: .arrow)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct SpinningCircleButton: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 2)
                .frame(width: 24, height: 24)
            Circle()
                .trim(from: 0, to: 0.65)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

struct SidebarPromptLauncher: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var cmuxConfigStore: CmuxConfigStore

    private static let accent = Color(red: 75 / 255, green: 123 / 255, blue: 1)
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var model = tabManager.promptLauncherModel
        return Group {
            if let config = cmuxConfigStore.promptLauncher {
                let repositoryID = config.repositories.contains(where: { $0.id == model.selectedRepository })
                    ? model.selectedRepository
                    : config.selectedDefaultRepositoryID
                let availableTargets = config.targets(forRepositoryID: repositoryID)
                let targetID = config.targets.contains(where: { $0.id == model.selectedTarget })
                    ? model.selectedTarget
                    : config.selectedDefaultTargetID(forRepositoryID: repositoryID)
                let providerID = config.providers.contains(where: { $0.id == model.selectedProvider })
                    ? model.selectedProvider
                    : config.selectedDefaultProviderID
                let defaultTargetID = config.selectedDefaultTargetID(forRepositoryID: config.selectedDefaultRepositoryID)
                let isOnDefaultTarget = targetID == defaultTargetID
                    && repositoryID == config.selectedDefaultRepositoryID

                let isTargetSupported = model.isTargetSupported(config)
                let canSend = isTargetSupported
                    && !model.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let submit = {
                    model.launch(
                        config: config,
                        tabManager: tabManager,
                        configSourcePath: cmuxConfigStore.promptLauncherSourcePath,
                        globalConfigPath: cmuxConfigStore.globalConfigPath
                    )
                }

                let autoControl = Button {
                    model.resetDestination(config)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(isOnDefaultTarget
                             ? String(localized: "sidebar.prompt_launcher.auto", defaultValue: "Auto")
                             : String(localized: "sidebar.prompt_launcher.custom", defaultValue: "Custom"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(isOnDefaultTarget ? Color.white : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(isOnDefaultTarget ? Self.accent : Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(String(localized: "sidebar.prompt_launcher.autoTargetHelp",
                             defaultValue: "Reset to the default target and repository"))
                .accessibilityLabel(
                    String(localized: "sidebar.prompt_launcher.autoTarget", defaultValue: "Auto target")
                )
                .accessibilityValue(isOnDefaultTarget
                    ? String(localized: "sidebar.prompt_launcher.auto", defaultValue: "Auto")
                    : String(localized: "sidebar.prompt_launcher.custom", defaultValue: "Custom"))
                let shortcutHint = Text(String(localized: "sidebar.prompt_launcher.sendHint", defaultValue: "⌘↵ to send"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                let environmentControl = targetMenu(
                    choices: config.targets,
                    enabledIDs: Set(availableTargets.map(\.id)),
                    selectedID: targetID
                ) {
                    model.selectedTarget = $0
                }
                let agentControl = providerMenu(choices: config.providers, selectedID: providerID) {
                    model.selectedProvider = $0
                }
                let repositoryControl = repositoryMenu(choices: config.repositories, selectedID: repositoryID) {
                    model.selectRepository($0)
                }
                let sendControl = sendButton(isEnabled: canSend, action: submit)

                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            autoControl
                            Spacer(minLength: 0)
                            shortcutHint
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            autoControl
                            shortcutHint
                        }
                    }

                    VStack(spacing: 8) {
                        PromptTextEditorContainer(
                            text: $model.promptText,
                            placeholder: String(localized: "sidebar.prompt_launcher.placeholder",
                                                defaultValue: "What should the agent do?"),
                            isEditable: true,
                            onSubmit: submit
                        )
                        .frame(height: 104)

                        HStack(spacing: 6) {
                            environmentControl
                                .frame(minWidth: 0, maxWidth: 62)
                            agentControl
                                .frame(minWidth: 0, maxWidth: 66)
                            if !config.repositories.isEmpty { repositoryControl }
                            sendControl.fixedSize()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(PromptLauncherArrowCursorArea())

                        if !isTargetSupported {
                            Text(String(
                                localized: "sidebar.prompt_launcher.unsupportedEnvironment",
                                defaultValue: "Choose an environment supported by this repository."
                            ))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                    .background(
                        colorScheme == .dark ? Color(white: 0.075) : Color(NSColor.textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }

                    ForEach(model.visibleJobs) { job in
                        PromptLauncherPendingCard(
                            job: job,
                            onRetry: {
                                model.retry(
                                    job,
                                    config: config,
                                    tabManager: tabManager,
                                    configSourcePath: cmuxConfigStore.promptLauncherSourcePath,
                                    globalConfigPath: cmuxConfigStore.globalConfigPath
                                )
                            },
                            onDismiss: { model.dismiss(job) }
                        )
                    }

                    ForEach(model.closeJobs) { job in
                        PromptLauncherClosingCard(
                            job: job,
                            onRetry: { model.retry(job) },
                            onDismiss: { model.dismiss(job) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Divider() }
                .onAppear { model.configure(config) }
                .onChange(of: config) { _, newConfig in
                    model.configure(newConfig)
                }
            }
        }
    }

    private func targetMenu(
        choices: [CmuxPromptLauncherChoice], enabledIDs: Set<String>,
        selectedID: String, select: @escaping (String) -> Void
    ) -> some View {
        choiceMenu(
            title: String(localized: "sidebar.prompt_launcher.environmentLabel", defaultValue: "ENV"),
            choices: choices, selectedID: selectedID, enabledIDs: enabledIDs, select: select
        )
    }

    private func providerMenu(
        choices: [CmuxPromptLauncherChoice], selectedID: String, select: @escaping (String) -> Void
    ) -> some View {
        choiceMenu(
            title: String(localized: "sidebar.prompt_launcher.agentLabel", defaultValue: "AGENT"),
            choices: choices, selectedID: selectedID, select: select
        )
    }

    private func repositoryMenu(
        choices: [CmuxPromptLauncherChoice], selectedID: String, select: @escaping (String) -> Void
    ) -> some View {
        choiceMenu(
            title: String(localized: "sidebar.prompt_launcher.repoLabel", defaultValue: "REPO"),
            choices: choices, selectedID: selectedID, select: select
        )
    }

    private func choiceMenu(
        title: String,
        choices: [CmuxPromptLauncherChoice],
        selectedID: String,
        enabledIDs: Set<String>? = nil,
        select: @escaping (String) -> Void
    ) -> some View {
        let selectedTitle = choices.first { $0.id == selectedID }?.title ?? selectedID
        return Menu {
            Picker(title, selection: Binding(get: { selectedID }, set: select)) {
                ForEach(choices) { choice in
                    Text(choice.title).tag(choice.id)
                        .disabled(enabledIDs.map { !$0.contains(choice.id) } ?? false)
                }
            }
            .pickerStyle(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .lineLimit(1)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(.secondary)
                Text(selectedTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 6)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .clipped()
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(minWidth: 0, maxWidth: .infinity)
        .help(selectedTitle)
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
    }

    private func sendButton(isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isEnabled ? Color.white : Color.secondary.opacity(0.6))
                .frame(width: 30, height: 30)
                .background(isEnabled ? Self.accent : Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(!isEnabled)
        .accessibilityLabel(String(localized: "sidebar.prompt_launcher.send", defaultValue: "Send"))
    }

}

private struct PromptLauncherPendingCard: View {
    let job: PromptLauncherModel.Job
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        PromptLauncherOperationCard(
            title: job.displayTitle,
            detail: job.latestLine,
            isFailed: job.state == .failed,
            icon: "sparkles",
            onRetry: onRetry,
            onDismiss: onDismiss
        )
    }
}

private struct PromptLauncherClosingCard: View {
    let job: PromptLauncherModel.CloseJob
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        PromptLauncherOperationCard(
            title: job.workspaceName,
            detail: job.latestLine,
            isFailed: job.state == .failed,
            icon: "xmark.circle",
            onRetry: onRetry,
            onDismiss: onDismiss
        )
    }
}

private struct PromptLauncherOperationCard: View {
    let title: String
    let detail: String
    let isFailed: Bool
    let icon: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private func renderedMarkdown(_ markdown: String) -> Text {
        guard let rendered = SidebarMarkdownRenderer(markdown: markdown).workspaceDescription else {
            return Text(markdown)
        }
        let styled = rendered.applyingSidebarRowLinkPolicy(activeForegroundColor: nil)
        return Text(styled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: isFailed ? "exclamationmark.triangle.fill" : icon)
                    .foregroundStyle(isFailed ? Color.red : Color.accentColor)
                renderedMarkdown(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                if !isFailed {
                    SpinningCircleButton()
                        .scaleEffect(0.58)
                        .frame(width: 16, height: 16)
                }
            }

            renderedMarkdown(detail)
                .font(.system(size: 10))
                .foregroundStyle(isFailed ? Color.red : Color.secondary)
                .lineLimit(2)

            if isFailed {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Button(String(localized: "sidebar.prompt_launcher.retry", defaultValue: "Retry"), action: onRetry)
                    Button(String(localized: "sidebar.prompt_launcher.dismiss", defaultValue: "Dismiss"), action: onDismiss)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .medium))
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isFailed ? Color.red.opacity(0.08) : Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFailed ? Color.red.opacity(0.32) : Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
