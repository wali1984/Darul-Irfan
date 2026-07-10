import Foundation

/// Renders FTS snippet strings for display. The search index may wrap matched
/// terms in marker characters; this formatter bolds the marked ranges and
/// never lets a stray marker leak into the UI.
///
/// Marker handling (SearchIndexService's exact markers are decided by the
/// service team, so both common conventions are supported):
/// - Single guillemets '‹' / '›' are treated as match markers outright: they
///   are vanishingly rare in real content. If they turn out unbalanced, they
///   are stripped and the snippet is shown plain.
/// - ASCII '<' / '>' are treated as markers only when the whole snippet parses
///   as clean, non-nested pairs, because real text can legitimately contain
///   angle brackets. If parsing fails the snippet is shown exactly as-is.
enum SearchSnippetFormatter {
    /// Builds the display string, bolding any marked match ranges.
    static func attributedSnippet(from raw: String) -> AttributedString {
        if raw.contains("\u{2039}") || raw.contains("\u{203A}") {
            if let parsed = parse(raw, open: "\u{2039}", close: "\u{203A}") {
                return parsed
            }
            let stripped = raw
                .replacingOccurrences(of: "\u{2039}", with: "")
                .replacingOccurrences(of: "\u{203A}", with: "")
            return AttributedString(stripped)
        }
        if raw.contains("<"), raw.contains(">"),
           let parsed = parse(raw, open: "<", close: ">") {
            return parsed
        }
        return AttributedString(raw)
    }

    /// Single-pass parse of `open`…`close` marker pairs into a bolded
    /// AttributedString. Returns nil when markers are nested or unbalanced.
    private static func parse(
        _ raw: String,
        open: Character,
        close: Character
    ) -> AttributedString? {
        var output = AttributedString()
        var plainBuffer = ""
        var highlightBuffer = ""
        var insideMarker = false

        for character in raw {
            if character == open {
                guard !insideMarker else { return nil } // nested — not a marker
                if !plainBuffer.isEmpty {
                    output.append(AttributedString(plainBuffer))
                    plainBuffer = ""
                }
                insideMarker = true
            } else if character == close {
                guard insideMarker else { return nil } // close without open
                var highlighted = AttributedString(highlightBuffer)
                highlighted.inlinePresentationIntent = .stronglyEmphasized
                output.append(highlighted)
                highlightBuffer = ""
                insideMarker = false
            } else if insideMarker {
                highlightBuffer.append(character)
            } else {
                plainBuffer.append(character)
            }
        }

        guard !insideMarker else { return nil } // unterminated marker
        if !plainBuffer.isEmpty {
            output.append(AttributedString(plainBuffer))
        }
        return output
    }
}
