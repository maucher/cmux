public import Foundation

/// Pure text transform converting a workspace-description markdown string into
/// an `AttributedString`, preserving inline markdown attributes and original
/// whitespace/line breaks.
///
/// Shared foundation utility (not sidebar-specific); used to render workspace
/// descriptions in the sidebar and reusable anywhere a lightweight inline
/// markdown render is needed. Construct it with the markdown source and read
/// ``workspaceDescription``.
public struct SidebarMarkdownRenderer {
    private let markdown: String

    public init(markdown: String) {
        self.markdown = markdown
    }

    /// The markdown rendered into an `AttributedString`, interpreting only
    /// inline syntax and preserving whitespace. `nil` when it cannot be parsed.
    public var workspaceDescription: AttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard var rendered = try? AttributedString(markdown: markdown, options: options) else {
            return nil
        }
        Self.linkifyBareURLs(in: &rendered)
        return rendered
    }

    /// Adds tap targets to bare URLs that markdown's inline parser leaves as
    /// plain text (it only links `[text](url)` and autolinks `<url>`).
    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private static func linkifyBareURLs(in text: inout AttributedString) {
        let plain = String(text.characters)
        guard let detector = linkDetector, !plain.isEmpty else { return }
        let nsRange = NSRange(plain.startIndex..<plain.endIndex, in: plain)
        for match in detector.matches(in: plain, range: nsRange) {
            guard let url = match.url,
                  let stringRange = Range(match.range, in: plain),
                  let attrRange = Range(stringRange, in: text) else { continue }
            if text[attrRange].link == nil {
                text[attrRange].link = url
            }
        }
    }
}
