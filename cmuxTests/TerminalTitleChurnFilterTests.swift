import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite struct TerminalTitleChurnFilterTests {
    private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private let surfaceA = UUID()
    private let surfaceB = UUID()

    private func collapsed(_ rawTitle: String) -> String? {
        var filter = TerminalTitleChurnFilter()
        return filter.titleToDispatch(for: rawTitle, surfaceID: surfaceA)
    }

    @Test func collapsesLeadingSpinnerFramesToOneStableTitle() {
        for frame in Self.spinnerFrames {
            #expect(collapsed("\(frame) Working…") == "Working…")
        }

        var filter = TerminalTitleChurnFilter()
        let dispatched = Self.spinnerFrames.compactMap {
            filter.titleToDispatch(for: "\($0) Working…", surfaceID: surfaceA)
        }
        #expect(dispatched == ["Working…"])
    }

    @Test func preservesMeaningfulTitles() {
        #expect(collapsed("  ⠙  Building project") == "Building project")
        #expect(collapsed("⠋⠙⠹ Compiling") == "Compiling")
        #expect(collapsed("Build ⠋ step") == "Build ⠋ step")
        #expect(collapsed("  zsh — ~/proj  ") == "  zsh — ~/proj  ")
    }

    @Test func keepsDistinctStatesAndSurfacesIndependent() {
        var filter = TerminalTitleChurnFilter()
        #expect(filter.titleToDispatch(for: "⠋ Reading", surfaceID: surfaceA) == "Reading")
        #expect(filter.titleToDispatch(for: "⠙ Reading", surfaceID: surfaceA) == nil)
        #expect(filter.titleToDispatch(for: "⠹ Writing", surfaceID: surfaceA) == "Writing")
        #expect(filter.titleToDispatch(for: "⠋ Reading", surfaceID: surfaceB) == "Reading")
        #expect(filter.titleToDispatch(for: "⠙ Reading", surfaceID: surfaceB) == nil)
    }

    @Test func dropsSpinnerOnlyAndIdenticalPlainFrames() {
        var filter = TerminalTitleChurnFilter()
        #expect(filter.titleToDispatch(for: "⠋ Working…", surfaceID: surfaceA) == "Working…")
        #expect(filter.titleToDispatch(for: "⠙", surfaceID: surfaceA) == nil)
        #expect(filter.titleToDispatch(for: "⠹ Working…", surfaceID: surfaceA) == nil)
        #expect(filter.titleToDispatch(for: "zsh", surfaceID: surfaceA) == "zsh")
        #expect(filter.titleToDispatch(for: "zsh", surfaceID: surfaceA) == nil)
    }
}
