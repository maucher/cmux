import Foundation

extension CMUXCLI {
    /// `cmux projects get|set|assign`: manage sidebar projects
    /// (`~/.config/cmux/projects.json`).
    func runProjectsCommand(
        commandArgs: [String],
        client: SocketClient,
        jsonOutput: Bool
    ) throws {
        let subcommand = commandArgs.first?.lowercased() ?? "get"
        let rest = Array(commandArgs.dropFirst())

        switch subcommand {
        case "get":
            let response = try client.sendV2(method: "projects.get")
            if jsonOutput {
                print(jsonString(response))
            } else {
                print(jsonString(response["document"] ?? ["projects": []]))
            }
        case "set":
            let source = rest.first(where: { !$0.hasPrefix("--") || $0 == "-" }) ?? "-"
            let document = try Self.readProjectsDocument(source: source)
            let response = try client.sendV2(method: "projects.set", params: ["document": document])
            if jsonOutput {
                print(jsonString(response))
            } else {
                let ids = (response["projects"] as? [String]) ?? []
                let path = (response["path"] as? String) ?? ""
                print("OK \(ids.count) project(s) written to \(path)")
            }
        case "assign":
            let positionals = rest.filter { !$0.hasPrefix("--") }
            guard positionals.count == 2 else {
                throw CLIError(message: Self.projectsUsage())
            }
            let projectArgument = positionals[1]
            let projectValue: Any = projectArgument.lowercased() == "none" ? NSNull() : projectArgument
            let response = try client.sendV2(
                method: "workspace.set_project",
                params: ["workspace_id": positionals[0], "project_id": projectValue]
            )
            if jsonOutput {
                print(jsonString(response))
            } else {
                let project = (response["project_id"] as? String) ?? "none"
                print("OK \(positionals[0]) -> \(project)")
            }
        case "help", "--help", "-h":
            print(Self.projectsUsage())
        default:
            throw CLIError(message: Self.projectsUsage())
        }
    }

    /// Reads and parses the whole projects document locally so invalid JSON
    /// fails before anything reaches the app.
    static func readProjectsDocument(source: String) throws -> [String: Any] {
        let data: Data
        if source == "-" {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            let path = (source as NSString).expandingTildeInPath
            guard let contents = FileManager.default.contents(atPath: path) else {
                throw CLIError(message: "cannot read projects file: \(source)")
            }
            data = contents
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CLIError(message: "projects document is not valid JSON: \(error.localizedDescription)")
        }
        guard let document = object as? [String: Any], document["projects"] is [Any] else {
            throw CLIError(message: "projects document must be an object like {\"projects\": [...]}")
        }
        return document
    }

    static func projectsUsage() -> String {
        """
        Usage: cmux projects <get|set|assign>

        Manage sidebar projects stored in ~/.config/cmux/projects.json. Session
        cards are grouped Pinned, then projects in order, then Other; the prompt
        launcher picks a project instead of a repository.

        Subcommands:
          get                                   Print the effective projects document as JSON.
          set [file|-]                          Replace the whole document (default: read stdin).
                                                Invalid documents are rejected without writing.
          assign <workspace-id|ref> <project-id|none>
                                                Move a workspace to a project, or clear it.

        Document:
          {"projects": [{"id": "backend", "title": "Backend", "args": ["--repo", "backend"],
                         "allowedTargets": ["devbox"], "defaultTarget": "devbox"}]}

        Example:
          cmux projects get > projects.json && cmux projects set projects.json
          cmux projects assign workspace:3 backend
        """
    }
}
