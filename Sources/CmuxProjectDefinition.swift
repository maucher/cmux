import Foundation

/// A sidebar project: a session-card group and the prompt launcher destination
/// whose args, allowed targets and default target replace the repository
/// choice. It has exactly the shape of a launcher repository entry.
typealias CmuxProjectDefinition = CmuxPromptLauncherChoice

extension CmuxProjectDefinition {
    static let pinnedID = "pinned"
    static let otherID = "other"
    static let localTargetID = "local"

    static func implicitPinned(targetIDs: Set<String>?) -> CmuxProjectDefinition {
        let hasLocal = targetIDs?.contains(localTargetID) == true
        return CmuxProjectDefinition(
            id: pinnedID,
            title: String(localized: "sidebar.sessionGroup.pinned", defaultValue: "Pinned"),
            allowedTargets: hasLocal ? [localTargetID] : nil,
            defaultTarget: hasLocal ? localTargetID : nil
        )
    }
}

enum CmuxProjectsConfigError: LocalizedError, Equatable {
    case invalidJSON(String)
    case invalidID(String)
    case reservedID(String)
    case blankTitle(String)
    case duplicateID(String)
    case noAllowedTargets(String)
    case unknownTarget(project: String, target: String)
    case disallowedDefaultTarget(project: String, target: String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "projects document is not valid: \(detail)"
        case .invalidID(let id):
            return "project id '\(id)' may contain only letters, numbers, dots, underscores, and hyphens"
        case .reservedID(let id):
            return "project id '\(id)' is reserved"
        case .blankTitle(let id):
            return "project '\(id)' must have a non-blank title"
        case .duplicateID(let id):
            return "project id '\(id)' is used more than once"
        case .noAllowedTargets(let id):
            return "project '\(id)' must allow at least one target"
        case .unknownTarget(let project, let target):
            return "project '\(project)' references unknown target '\(target)'"
        case .disallowedDefaultTarget(let project, let target):
            return "project '\(project)' defaultTarget '\(target)' must be one of its allowedTargets"
        }
    }
}

/// The `projects.json` document: `{"projects": [...]}`.
struct CmuxProjectsDocument: Codable, Sendable, Equatable {
    var projects: [CmuxProjectDefinition] = []

    /// Decodes and validates a document. `targetIDs` is the configured prompt
    /// launcher target set; target references are only checked when it is known.
    static func validated(_ data: Data, targetIDs: Set<String>?) throws -> CmuxProjectsDocument {
        let document: CmuxProjectsDocument
        do {
            document = try JSONDecoder().decode(CmuxProjectsDocument.self, from: data)
        } catch let error as DecodingError {
            throw CmuxProjectsConfigError.invalidJSON(Self.describe(error))
        } catch {
            throw CmuxProjectsConfigError.invalidJSON(error.localizedDescription)
        }
        try document.validate(targetIDs: targetIDs)
        return document
    }

    func validate(targetIDs: Set<String>?) throws {
        var seen = Set<String>()
        for project in projects {
            guard project.id.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
                throw CmuxProjectsConfigError.invalidID(project.id)
            }
            guard project.id != CmuxProjectDefinition.otherID else {
                throw CmuxProjectsConfigError.reservedID(project.id)
            }
            guard !project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CmuxProjectsConfigError.blankTitle(project.id)
            }
            guard seen.insert(project.id).inserted else {
                throw CmuxProjectsConfigError.duplicateID(project.id)
            }
            guard let targetIDs else { continue }
            let allowed = project.allowedTargets ?? Array(targetIDs)
            if project.allowedTargets != nil, allowed.isEmpty {
                throw CmuxProjectsConfigError.noAllowedTargets(project.id)
            }
            if let unknown = allowed.first(where: { !targetIDs.contains($0) }) {
                throw CmuxProjectsConfigError.unknownTarget(project: project.id, target: unknown)
            }
            if let defaultTarget = project.defaultTarget {
                guard targetIDs.contains(defaultTarget) else {
                    throw CmuxProjectsConfigError.unknownTarget(project: project.id, target: defaultTarget)
                }
                guard allowed.contains(defaultTarget) else {
                    throw CmuxProjectsConfigError.disallowedDefaultTarget(project: project.id, target: defaultTarget)
                }
            }
        }
    }

    /// Configured projects in order with the implicit `pinned` project appended
    /// when the document does not declare one.
    func resolvedProjects(targetIDs: Set<String>?) -> [CmuxProjectDefinition] {
        Self.withImplicitPinned(projects, targetIDs: targetIDs)
    }

    static func withImplicitPinned(
        _ projects: [CmuxProjectDefinition],
        targetIDs: Set<String>?
    ) -> [CmuxProjectDefinition] {
        guard !projects.contains(where: { $0.id == CmuxProjectDefinition.pinnedID }) else { return projects }
        return projects + [.implicitPinned(targetIDs: targetIDs)]
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context),
             .keyNotFound(_, let context),
             .typeMismatch(_, let context),
             .valueNotFound(_, let context):
            let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
                .joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

/// Reads and atomically writes the app-owned `projects.json`.
struct ProjectsConfigStore {
    static let fileName = "projects.json"

    enum LoadResult: Equatable {
        case missing
        case loaded(CmuxProjectsDocument)
        case invalid(String)
    }

    let path: String

    /// Uses `explicitPath` when given, else `projects.json` next to `cmux.json`.
    init(explicitPath: String?, globalConfigPath: String) {
        path = explicitPath.flatMap { $0.isEmpty ? nil : $0 }
            ?? ((globalConfigPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(Self.fileName)
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Structural validation only; target references are checked by the caller
    /// that knows the prompt launcher targets.
    func load() -> LoadResult {
        guard let data = FileManager.default.contents(atPath: path) else { return .missing }
        do {
            return .loaded(try CmuxProjectsDocument.validated(data, targetIDs: nil))
        } catch {
            return .invalid(error.localizedDescription)
        }
    }

    /// Validates raw JSON, then replaces the file through a temporary sibling.
    /// Nothing is written when validation fails.
    @discardableResult
    func save(data: Data, targetIDs: Set<String>?) throws -> CmuxProjectsDocument {
        let document = try CmuxProjectsDocument.validated(data, targetIDs: targetIDs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try Self.atomicWrite(try encoder.encode(document), to: path)
        return document
    }

    private static func atomicWrite(_ data: Data, to path: String) throws {
        let fileManager = FileManager.default
        // Resolve a symlink so a dotfiles-managed file is updated in place
        // instead of being replaced by a regular file.
        let destinationURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let directoryURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let temporaryURL = directoryURL
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        var payload = data
        payload.append(0x0A)
        try payload.write(to: temporaryURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: temporaryURL.path)
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }
}

extension CmuxConfigStore {
    /// Resolves the sidebar projects for `loadAll()`. A missing file falls back
    /// to the launcher repositories; an invalid file is reported as a config
    /// issue and also falls back, so the sidebar never loses its groups.
    func resolveProjects(
        promptLauncher: CmuxPromptLauncherDefinition?,
        issues: inout [CmuxConfigIssue]
    ) -> (projects: [CmuxProjectDefinition], source: ProjectsSource) {
        let targetIDs = promptLauncher.map { Set($0.targets.map(\.id)) }
        let fallback = promptLauncher?.repositories ?? []
        switch projectsStore.load() {
        case .missing:
            return (CmuxProjectsDocument.withImplicitPinned(fallback, targetIDs: targetIDs), .repositories)
        case .invalid(let message):
            issues.append(CmuxConfigIssue(
                kind: .schemaError,
                settingName: "projects",
                sourcePath: projectsStore.path,
                message: message
            ))
            return (CmuxProjectsDocument.withImplicitPinned(fallback, targetIDs: targetIDs), .repositories)
        case .loaded(let document):
            // Target references are advisory at load time: the launcher drops
            // unknown targets, and `cmux projects set` rejects them strictly.
            if let targetIDs {
                do {
                    try document.validate(targetIDs: targetIDs)
                } catch {
                    issues.append(CmuxConfigIssue(
                        kind: .schemaError,
                        settingName: "projects",
                        sourcePath: projectsStore.path,
                        message: error.localizedDescription
                    ))
                }
            }
            return (document.resolvedProjects(targetIDs: targetIDs), .file)
        }
    }
}
