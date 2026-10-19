import Foundation

/// A collapsible sidebar section that groups sessions by project.
struct SessionCardGroup: Equatable, Identifiable {
    static let pinnedID = CmuxProjectDefinition.pinnedID
    static let otherID = CmuxProjectDefinition.otherID

    let id: String
    let title: String

    static let pinned = SessionCardGroup(
        id: pinnedID,
        title: String(localized: "sidebar.sessionGroup.pinned", defaultValue: "Pinned")
    )

    static let other = SessionCardGroup(
        id: otherID,
        title: String(localized: "sidebar.sessionGroup.other", defaultValue: "Other")
    )

    /// Pinned first, then configured projects in config order, then Other.
    static func groups(projects: [CmuxProjectDefinition]) -> [SessionCardGroup] {
        let pinnedProject = projects.first { $0.id == pinnedID }
        let pinnedGroup = pinnedProject.map {
            SessionCardGroup(id: pinnedID, title: $0.title)
        } ?? .pinned
        let projectGroups = projects
            .filter { $0.id != pinnedID && $0.id != otherID }
            .map { SessionCardGroup(id: $0.id, title: $0.title) }
        return [pinnedGroup] + projectGroups + [.other]
    }

    static func resolveID(
        projectId: String?,
        isPinned: Bool,
        projects: [CmuxProjectDefinition]
    ) -> String {
        if isPinned || projectId == pinnedID {
            return pinnedID
        }
        guard let projectId, projectId != otherID,
              projects.contains(where: { $0.id == projectId }) else {
            return otherID
        }
        return projectId
    }
}
