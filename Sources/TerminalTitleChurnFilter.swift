import Foundation

/// Collapses frame-by-frame terminal-title churn before it reaches workspace UI.
///
/// Codex and other CLI tools animate a leading Braille spinner in the terminal
/// title. Without normalization, every frame publishes a different title and
/// forces AppKit/SwiftUI to lay out the tab and workspace chrome again.
@MainActor
struct TerminalTitleChurnFilter {
    private var lastDispatchedTitleBySurfaceID: [UUID: String] = [:]
    private var retainedSurfaceIDs: [UUID] = []

    mutating func titleToDispatch(for rawTitle: String, surfaceID: UUID) -> String? {
        let stableTitle = collapseSpinnerFrames(rawTitle)

        // A spinner-only frame carries no useful title and must not blank the
        // stable label from a previous frame.
        if stableTitle.isEmpty,
           !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        guard lastDispatchedTitleBySurfaceID[surfaceID] != stableTitle else {
            return nil
        }

        rememberSurfaceIDIfNeeded(surfaceID)
        lastDispatchedTitleBySurfaceID[surfaceID] = stableTitle
        return stableTitle
    }

    private mutating func rememberSurfaceIDIfNeeded(_ surfaceID: UUID) {
        guard lastDispatchedTitleBySurfaceID[surfaceID] == nil else { return }
        retainedSurfaceIDs.append(surfaceID)
        if retainedSurfaceIDs.count > 32 {
            let removedSurfaceID = retainedSurfaceIDs.removeFirst()
            lastDispatchedTitleBySurfaceID.removeValue(forKey: removedSurfaceID)
        }
    }

    private func collapseSpinnerFrames(_ rawTitle: String) -> String {
        var cursor = Substring(rawTitle)

        // Peek past leading whitespace without changing ordinary titles.
        while let character = cursor.first, character.isWhitespace {
            cursor = cursor.dropFirst()
        }
        guard let first = cursor.first, isBrailleSpinnerGlyph(first) else {
            return rawTitle
        }

        while let character = cursor.first, isBrailleSpinnerGlyph(character) {
            cursor = cursor.dropFirst()
        }
        while let character = cursor.first, character.isWhitespace {
            cursor = cursor.dropFirst()
        }
        return String(cursor)
    }

    private func isBrailleSpinnerGlyph(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        return (0x2800...0x28FF).contains(scalar.value)
    }
}
