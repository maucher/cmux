import Foundation

struct SessionCardSnapshot: Equatable {
    enum Host: Equatable {
        case laptop
        case devbox

        var displayName: String {
            switch self {
            case .laptop:
                return String(localized: "sidebar.sessionCard.host.laptop", defaultValue: "laptop")
            case .devbox:
                return String(localized: "sidebar.sessionCard.host.devbox", defaultValue: "devbox")
            }
        }
    }

    enum Badge: Equatable {
        case indexedWorktree(Int)
        case unindexedHost(Host)
    }

    enum Mode: Equatable {
        case plan
        case defaultMode
        case edit

        init(metadataValue: String?) {
            let normalized = metadataValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
                ?? ""
            if normalized.contains("plan") {
                self = .plan
            } else if normalized.contains("edit") {
                self = .edit
            } else {
                self = .defaultMode
            }
        }

        var displayName: String {
            switch self {
            case .plan:
                return String(localized: "sidebar.sessionCard.mode.plan", defaultValue: "Plan")
            case .defaultMode:
                return String(localized: "sidebar.sessionCard.mode.default", defaultValue: "Default")
            case .edit:
                return String(localized: "sidebar.sessionCard.mode.edit", defaultValue: "Edit")
            }
        }
    }

    enum Status: Equatable {
        case connected
        case running
        case waiting
        case idle

        init?(metadataValue: String?) {
            let normalized = metadataValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
                ?? ""
            switch normalized {
            case "connected", "online", "ready":
                self = .connected
            case "running", "working", "busy", "in-progress", "processing":
                self = .running
            case "waiting", "needs-input", "needsinput", "blocked", "paused":
                self = .waiting
            case "idle", "disconnected", "offline":
                self = .idle
            default:
                return nil
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .connected:
                return String(localized: "sidebar.sessionCard.status.connected", defaultValue: "Connected")
            case .running:
                return String(localized: "sidebar.sessionCard.status.running", defaultValue: "Running")
            case .waiting:
                return String(localized: "sidebar.sessionCard.status.waiting", defaultValue: "Waiting")
            case .idle:
                return String(localized: "sidebar.sessionCard.status.idle", defaultValue: "Idle")
            }
        }
    }

    struct Diff: Equatable {
        let added: Int
        let deleted: Int

        init(added: Int, deleted: Int) {
            self.added = max(0, abs(added))
            self.deleted = max(0, abs(deleted))
        }

        var isEmpty: Bool {
            added == 0 && deleted == 0
        }

        static func parseCount(_ value: String?) -> Int {
            guard let value else { return 0 }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return 0 }
            if let parsed = Int(trimmed) {
                return abs(parsed)
            }
            let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
            return abs(Int(stripped) ?? 0)
        }
    }

    struct StatusLabel: Equatable {
        let value: String
        let icon: String?
        let colorHex: String?
    }

    let workspaceNumber: Int
    let badge: Badge
    let name: String
    let colorHex: String
    let host: Host
    let branchName: String?
    let modelName: String?
    let mode: Mode
    let status: Status
    let statusLabel: StatusLabel?
    let diff: Diff

    init(
        workspaceNumber: Int,
        name: String,
        colorHex: String,
        host: Host,
        branchName: String?,
        modelName: String?,
        mode: Mode,
        status: Status,
        diff: Diff,
        badge: Badge? = nil,
        statusLabel: StatusLabel? = nil
    ) {
        self.workspaceNumber = min(10, max(1, workspaceNumber))
        self.badge = badge ?? .indexedWorktree(self.workspaceNumber)
        self.name = Self.nonEmpty(name) ?? String(localized: "sidebar.sessionCard.defaultName", defaultValue: "Workspace")
        self.colorHex = colorHex
        self.host = host
        self.branchName = Self.nonEmpty(branchName)
        self.modelName = Self.nonEmpty(modelName)
        self.mode = mode
        self.status = status
        self.statusLabel = statusLabel
        self.diff = diff
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func indexedWorktreeNumber(in rawValue: String) -> Int? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let lowercased = value.lowercased()
        if lowercased.hasPrefix("[wk"),
           let closingBracket = lowercased.firstIndex(of: "]") {
            let slotText = lowercased[..<closingBracket].dropFirst(3)
            if let slot = Int(slotText) {
                return slot
            }
        }
        if let slot = leadingKeycapWorktreeNumber(in: lowercased) {
            return slot
        }

        let normalizedPath = lowercased
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "~", with: "/")
        for component in normalizedPath.split(separator: "/", omittingEmptySubsequences: true) {
            if let slot = indexedWorktreeNumber(inPathComponent: component, prefix: "ws-wk") {
                return slot
            }
            if let slot = indexedWorktreeNumber(inPathComponent: component, prefix: "wk") {
                return slot
            }
            if let marker = component.range(of: "-wk", options: .backwards),
               let slot = Int(component[marker.upperBound...]) {
                return slot
            }
        }
        return nil
    }

    private static func leadingKeycapWorktreeNumber(in value: String) -> Int? {
        let scalars = Array(value.unicodeScalars)
        guard let first = scalars.first,
              let slot = Int(String(first)),
              slot >= 0
        else {
            return nil
        }

        var index = 1
        if index < scalars.count, scalars[index].value == 0xFE0F {
            index += 1
        }
        guard index < scalars.count, scalars[index].value == 0x20E3 else {
            return nil
        }
        return slot
    }

    private static func indexedWorktreeNumber(
        inPathComponent component: Substring,
        prefix: String
    ) -> Int? {
        guard component.hasPrefix(prefix) else { return nil }
        let slotText = component.dropFirst(prefix.count)
        let digits = slotText.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        let remainder = slotText.dropFirst(digits.count)
        guard remainder.isEmpty || String(remainder) == ".sh" else { return nil }
        return Int(digits)
    }
}
