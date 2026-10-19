import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class CmuxProjectsConfigTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-projects-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    private var projectsPath: String {
        directory.appendingPathComponent("projects.json").path
    }

    private var globalConfigPath: String {
        directory.appendingPathComponent("cmux.json").path
    }

    // MARK: Decoding and validation

    func testDecodesProjectShapeWithChoiceAliasesAndColor() throws {
        let document = try CmuxProjectsDocument.validated(data("""
        {"projects": [
          {"id": "backend", "label": " Backend ", "arguments": ["--repo", " backend ", ""],
           "allowedTargets": ["devbox"], "defaultTarget": "devbox"},
          {"id": "docs"}
        ]}
        """), targetIDs: ["local", "devbox"])

        XCTAssertEqual(document.projects.map(\.id), ["backend", "docs"])
        XCTAssertEqual(document.projects[0].title, "Backend")
        XCTAssertEqual(document.projects[0].args, ["--repo", "backend"])
        XCTAssertEqual(document.projects[0].allowedTargets, ["devbox"])
        XCTAssertEqual(document.projects[0].defaultTarget, "devbox")
        XCTAssertEqual(document.projects[1].title, "docs")
    }

    func testRejectsReservedOtherID() {
        XCTAssertThrowsError(try CmuxProjectsDocument.validated(
            data(#"{"projects": [{"id": "other"}]}"#), targetIDs: nil
        )) { error in
            XCTAssertEqual(error as? CmuxProjectsConfigError, .reservedID("other"))
        }
    }

    func testRejectsDuplicateIDs() {
        XCTAssertThrowsError(try CmuxProjectsDocument.validated(
            data(#"{"projects": [{"id": "a"}, {"id": "a"}]}"#), targetIDs: nil
        )) { error in
            XCTAssertEqual(error as? CmuxProjectsConfigError, .duplicateID("a"))
        }
    }

    func testRejectsInvalidSlugAndMissingProjectsKey() {
        XCTAssertThrowsError(try CmuxProjectsDocument.validated(
            data(#"{"projects": [{"id": "has space"}]}"#), targetIDs: nil
        ))
        XCTAssertThrowsError(try CmuxProjectsDocument.validated(data(#"{"items": []}"#), targetIDs: nil))
        XCTAssertThrowsError(try CmuxProjectsDocument.validated(data("not json"), targetIDs: nil))
    }

    func testTargetsAreValidatedOnlyWhenKnown() throws {
        let json = data(#"{"projects": [{"id": "a", "allowedTargets": ["ghost"]}]}"#)
        XCTAssertNoThrow(try CmuxProjectsDocument.validated(json, targetIDs: nil))
        XCTAssertThrowsError(try CmuxProjectsDocument.validated(json, targetIDs: ["local"])) { error in
            XCTAssertEqual(error as? CmuxProjectsConfigError, .unknownTarget(project: "a", target: "ghost"))
        }
        XCTAssertThrowsError(try CmuxProjectsDocument.validated(
            data(#"{"projects": [{"id": "a", "allowedTargets": ["local"], "defaultTarget": "devbox"}]}"#),
            targetIDs: ["local", "devbox"]
        )) { error in
            XCTAssertEqual(error as? CmuxProjectsConfigError, .disallowedDefaultTarget(project: "a", target: "devbox"))
        }
    }

    func testImplicitPinnedIsAppendedWhenMissing() {
        let document = CmuxProjectsDocument(projects: [CmuxProjectDefinition(id: "backend")])
        let withLocal = document.resolvedProjects(targetIDs: ["local", "devbox"])
        XCTAssertEqual(withLocal.map(\.id), ["backend", "pinned"])
        XCTAssertEqual(withLocal.last?.allowedTargets, ["local"])
        XCTAssertEqual(withLocal.last?.defaultTarget, "local")

        let withoutLocal = document.resolvedProjects(targetIDs: ["devbox"])
        XCTAssertNil(withoutLocal.last?.allowedTargets)
        XCTAssertNil(withoutLocal.last?.defaultTarget)

        let explicit = CmuxProjectsDocument(projects: [
            CmuxProjectDefinition(id: "pinned", title: "Laptop"),
            CmuxProjectDefinition(id: "backend"),
        ])
        XCTAssertEqual(explicit.resolvedProjects(targetIDs: nil).map(\.title), ["Laptop", "backend"])
    }

    // MARK: Store

    func testStorePathResolution() {
        XCTAssertEqual(
            ProjectsConfigStore(explicitPath: "/x/p.json", globalConfigPath: "/g/cmux.json").path,
            "/x/p.json"
        )
        XCTAssertEqual(
            ProjectsConfigStore(explicitPath: nil, globalConfigPath: "/g/cmux.json").path,
            "/g/projects.json"
        )
    }

    func testSaveRejectsInvalidDocumentWithoutWriting() throws {
        let store = ProjectsConfigStore(explicitPath: projectsPath, globalConfigPath: globalConfigPath)
        XCTAssertThrowsError(try store.save(data: data(#"{"projects": [{"id": "other"}]}"#), targetIDs: nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectsPath))

        try store.save(data: data(#"{"projects": [{"id": "backend"}]}"#), targetIDs: nil)
        let before = try Data(contentsOf: URL(fileURLWithPath: projectsPath))
        XCTAssertThrowsError(try store.save(
            data: data(#"{"projects": [{"id": "a", "allowedTargets": ["ghost"]}]}"#),
            targetIDs: ["local"]
        ))
        XCTAssertThrowsError(try store.save(data: data("{"), targetIDs: nil))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: projectsPath)), before)
    }

    func testSaveRoundTripsThroughLoad() throws {
        let store = ProjectsConfigStore(explicitPath: projectsPath, globalConfigPath: globalConfigPath)
        let document = try store.save(
            data: data(#"{"projects": [{"id": "backend", "title": "Backend", "args": ["backend"]}]}"#),
            targetIDs: nil
        )
        XCTAssertEqual(document.projects.first?.args, ["backend"])
        XCTAssertEqual(store.load(), .loaded(document))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, ["projects.json"])
    }

    // MARK: CmuxConfigStore

    private func writeGlobalConfig(_ json: String) throws {
        try data(json).write(to: URL(fileURLWithPath: globalConfigPath))
    }

    private static let launcherJSON = """
    {"promptLauncher": {
      "command": "workspace-launch --repo {{repository.args}} {{prompt}}",
      "targets": [{"id": "local"}, {"id": "devbox"}],
      "providers": [{"id": "claude"}],
      "repositories": [{"id": "legacy", "title": "Legacy", "args": ["legacy"]}]
    }}
    """

    @MainActor
    func testConfigStoreFallsBackToRepositoriesWhenFileMissing() throws {
        try writeGlobalConfig(Self.launcherJSON)
        let store = CmuxConfigStore(globalConfigPath: globalConfigPath, projectsConfigPath: projectsPath)
        store.loadAll()
        XCTAssertEqual(store.projectsSource, .repositories)
        XCTAssertEqual(store.projects.map(\.id), ["legacy", "pinned"])
        XCTAssertEqual(store.projects.first?.args, ["legacy"])
        XCTAssertEqual(store.projects.last?.defaultTarget, "local")
    }

    @MainActor
    func testConfigStoreLoadsProjectsFile() throws {
        try writeGlobalConfig(Self.launcherJSON)
        try data(#"{"projects": [{"id": "backend", "allowedTargets": ["devbox"]}, {"id": "docs"}]}"#)
            .write(to: URL(fileURLWithPath: projectsPath))
        let store = CmuxConfigStore(globalConfigPath: globalConfigPath, projectsConfigPath: projectsPath)
        store.loadAll()
        XCTAssertEqual(store.projectsSource, .file)
        XCTAssertEqual(store.projects.map(\.id), ["backend", "docs", "pinned"])
        XCTAssertFalse(store.configurationIssues.contains { $0.settingName == "projects" })
    }

    @MainActor
    func testConfigStoreReportsInvalidProjectsFileAndFallsBack() throws {
        try writeGlobalConfig(Self.launcherJSON)
        try data(#"{"projects": [{"id": "other"}]}"#).write(to: URL(fileURLWithPath: projectsPath))
        let store = CmuxConfigStore(globalConfigPath: globalConfigPath, projectsConfigPath: projectsPath)
        store.loadAll()
        XCTAssertEqual(store.projectsSource, .repositories)
        XCTAssertEqual(store.projects.map(\.id), ["legacy", "pinned"])
        XCTAssertTrue(store.configurationIssues.contains { $0.settingName == "projects" })
    }
}
