import Foundation

/// `projects.get`, `projects.set` and `workspace.set_project`: sidebar project
/// management for `cmux projects`.
extension TerminalController {
    @MainActor
    private func v2ProjectsConfigStore(params: [String: Any]) -> CmuxConfigStore? {
        if let store = v2ResolveTabManager(params: params)?.cmuxConfigStore {
            return store
        }
        return AppDelegate.shared?.reloadableConfigStores.compactMap { $0 as? CmuxConfigStore }.first
    }

    @MainActor
    private func v2ProjectsJSONObject(_ projects: [CmuxProjectDefinition]) -> [[String: Any]] {
        let encoder = JSONEncoder()
        return projects.compactMap { project in
            guard let data = try? encoder.encode(project),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    @MainActor
    func v2ProjectsGet(params: [String: Any]) -> V2CallResult {
        guard let store = v2ProjectsConfigStore(params: params) else {
            return .err(code: "unavailable", message: "cmux config is not available", data: nil)
        }
        return .ok([
            "path": store.projectsStore.path,
            "file_exists": store.projectsStore.fileExists,
            "source": store.projectsSource.rawValue,
            "document": ["projects": v2ProjectsJSONObject(store.projects)],
        ])
    }

    @MainActor
    func v2ProjectsSet(params: [String: Any]) -> V2CallResult {
        guard let store = v2ProjectsConfigStore(params: params) else {
            return .err(code: "unavailable", message: "cmux config is not available", data: nil)
        }
        guard let document = params["document"],
              JSONSerialization.isValidJSONObject(document),
              let data = try? JSONSerialization.data(withJSONObject: document) else {
            return .err(code: "invalid_params", message: "document must be a JSON object like {\"projects\": [...]}", data: nil)
        }
        let targetIDs = store.promptLauncher.map { Set($0.targets.map(\.id)) }
        let saved: CmuxProjectsDocument
        do {
            saved = try store.projectsStore.save(data: data, targetIDs: targetIDs)
        } catch let error as CmuxProjectsConfigError {
            return .err(code: "invalid_params", message: error.localizedDescription, data: nil)
        } catch {
            return .err(code: "write_failed", message: error.localizedDescription, data: nil)
        }
        if let appDelegate = AppDelegate.shared {
            appDelegate.reloadCmuxConfigStores(source: "projects.set")
        } else {
            store.loadAll()
        }
        return .ok([
            "path": store.projectsStore.path,
            "projects": saved.projects.map(\.id),
        ])
    }

    @MainActor
    func v2WorkspaceSetProject(params: [String: Any]) -> V2CallResult {
        guard let workspaceId = v2UUID(params, "workspace_id") else {
            return .err(code: "invalid_params", message: "Missing or invalid workspace_id", data: nil)
        }
        let rawProject = params["project_id"]
        let projectId: String?
        if rawProject == nil || rawProject is NSNull {
            projectId = nil
        } else if let value = rawProject as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            projectId = trimmed.isEmpty ? nil : trimmed
        } else {
            return .err(code: "invalid_params", message: "project_id must be a string or null", data: nil)
        }
        guard let tabManager = v2ResolveTabManager(params: params),
              let workspace = tabManager.tabs.first(where: { $0.id == workspaceId }) else {
            return .err(code: "not_found", message: "Workspace not found", data: nil)
        }
        if let projectId {
            let projects = tabManager.cmuxConfigStore?.projects ?? []
            guard projects.contains(where: { $0.id == projectId }) else {
                return .err(
                    code: "invalid_params",
                    message: "Unknown project '\(projectId)'. Known projects: \(projects.map(\.id).joined(separator: ", "))",
                    data: nil
                )
            }
        }
        if workspace.projectId != projectId {
            workspace.projectId = projectId
        }
        return .ok([
            "workspace_id": workspace.id.uuidString,
            "project_id": v2OrNull(projectId),
        ])
    }
}
