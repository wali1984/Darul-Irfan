import SwiftUI

/// A place in a book's text that opens something: the ayah a page cites or
/// quotes, the narration it quotes, or the biography of a narrator it names.
struct BookLink: Codable, Sendable, Equatable {
    /// The words on the page, exactly as they are printed there.
    var m: String
    /// What they open: "q:2:255", "q:2:255-257", "h:<canonical id>" or
    /// "n:<narrator id>".
    var t: String
}

/// What a link opens.
enum BookLinkTarget: Identifiable, Equatable {
    case ayah(surah: Int, ayah: Int)
    /// `bookID|displayNumber|sourceSequence`.
    case hadith(canonicalID: String)
    case narrator(id: Int)

    var id: String {
        switch self {
        case .ayah(let surah, let ayah): return "q:\(surah):\(ayah)"
        case .hadith(let canonicalID): return "h:\(canonicalID)"
        case .narrator(let id): return "n:\(id)"
        }
    }

    /// Reads a link's target. A range of ayat opens at its first ayah.
    init?(_ raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        switch parts[0] {
        case "q":
            let numbers = parts[1].split(separator: ":").map(String.init)
            guard numbers.count == 2, let surah = Int(numbers[0]) else { return nil }
            let first = numbers[1].split(separator: "-").first.map(String.init) ?? numbers[1]
            guard let ayah = Int(first), (1...114).contains(surah), ayah >= 1 else { return nil }
            self = .ayah(surah: surah, ayah: ayah)
        case "h":
            self = .hadith(canonicalID: parts[1])
        case "n":
            guard let id = Int(parts[1]) else { return nil }
            self = .narrator(id: id)
        default:
            return nil
        }
    }
}

/// Finds a page's links in its text. A paragraph is searched whole, so that
/// a name cut by a printed line's end or by a quotation inside it is still a
/// link; each of its runs then shows its part of the link.
enum BookLinkMatcher {
    struct Piece: Equatable {
        var text: String
        /// The link's place in the page's list; nil for plain words.
        var link: Int?
    }

    /// A link's place in a text, counted in UTF-16.
    struct Mark: Equatable {
        var range: Range<Int>
        var link: Int
    }

    /// Every place in `string` that one of `links` names and that opens
    /// something, in order. The longest names are placed first, so a whole
    /// reference wins over a shorter one inside it, and no word is linked
    /// twice.
    static func marks(in string: String, links: [BookLink]) -> [Mark] {
        guard !string.isEmpty, !links.isEmpty else { return [] }
        let text = string as NSString
        var taken: [Mark] = []
        let order = links.indices.sorted { links[$0].m.count > links[$1].m.count }
        for index in order {
            let needle = links[index].m
            guard !needle.isEmpty else { continue }
            var from = 0
            while from < text.length {
                let rest = NSRange(location: from, length: text.length - from)
                let found = text.range(of: needle, options: .literal, range: rest)
                guard found.location != NSNotFound, found.length > 0 else { break }
                let range = found.location..<NSMaxRange(found)
                if !taken.contains(where: { $0.range.overlaps(range) }) {
                    taken.append(Mark(range: range, link: index))
                }
                from = range.upperBound
            }
        }
        return taken
            .filter { BookLinkTarget(links[$0.link].t) != nil }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// `string`, which stands at `start` in the text `marks` were found in,
    /// cut at their edges.
    static func pieces(of string: String, at start: Int, marks: [Mark]) -> [Piece] {
        let text = string as NSString
        var pieces: [Piece] = []
        var done = 0
        for mark in marks {
            let lower = max(done, mark.range.lowerBound - start)
            let upper = min(text.length, mark.range.upperBound - start)
            guard lower < upper else { continue }
            if done < lower {
                pieces.append(Piece(text: text.substring(with: NSRange(location: done, length: lower - done)), link: nil))
            }
            pieces.append(Piece(text: text.substring(with: NSRange(location: lower, length: upper - lower)), link: mark.link))
            done = upper
        }
        guard !pieces.isEmpty else { return [Piece(text: string, link: nil)] }
        if done < text.length {
            pieces.append(Piece(text: text.substring(from: done), link: nil))
        }
        return pieces
    }

    /// `string` cut at every place one of `links` names.
    static func pieces(of string: String, links: [BookLink]) -> [Piece] {
        pieces(of: string, at: 0, marks: marks(in: string, links: links))
    }

    /// A quotation's pieces, found in the whole of it where it was cut.
    static func pieces(
        of string: String,
        cutFrom quotation: BookPageFormatter.CutQuotation?,
        links: [BookLink]
    ) -> [Piece] {
        guard let quotation else { return pieces(of: string, links: links) }
        return pieces(of: string, at: quotation.start, marks: marks(in: quotation.whole, links: links))
    }

    /// Each run of a paragraph cut at its links. The paragraph is searched
    /// whole, with a space for each break between its runs. The words that
    /// finish it from the next page take that page's links (`carriedLinks`,
    /// counted on after `links`), and only those.
    static func pieces(
        ofParagraph runs: [BookPageFormatter.Run],
        carried: BookPageFormatter.Carried?,
        links: [BookLink],
        carriedLinks: [BookLink]
    ) -> [[Piece]] {
        var starts: [Int] = []
        var whole = ""
        var length = 0
        for run in runs {
            if !starts.isEmpty {
                whole += " "
                length += 1
            }
            starts.append(length)
            whole += run.text
            length += run.text.utf16.count
        }
        var own = length
        if let carried, carried.run < starts.count {
            own = min(length, starts[carried.run] + carried.offset)
        }
        let text = whole as NSString
        var found = marks(in: text.substring(to: own), links: links)
        for mark in marks(in: text.substring(from: own), links: carriedLinks) {
            let range = (mark.range.lowerBound + own)..<(mark.range.upperBound + own)
            found.append(Mark(range: range, link: mark.link + links.count))
        }
        return zip(runs, starts).map { run, start in pieces(of: run.text, at: start, marks: found) }
    }
}

private struct BookLinkFile: Codable, Sendable {
    var version: Int?
    /// Book id, then printed page number, then that page's links.
    var books: [String: [String: [BookLink]]]
}

/// Reads the bundled index of the references in the books' text.
///
/// Bundled and read straight from the app, like the ayah-to-bayan index: a
/// reader-only lookup that needs no table and no migration. An absent or
/// unreadable file means the text stays plain, never a failure to open a book.
final class BookLinkProvider: @unchecked Sendable {
    static let shared = BookLinkProvider()
    private let byBook: [String: [String: [BookLink]]]

    private init() {
        guard let url = SeedBundle.url(forFile: "book_links"),
              let raw = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(BookLinkFile.self, from: raw) else {
            byBook = [:]
            return
        }
        byBook = file.books
    }

    /// A book's links, by printed page.
    func links(bookID: String) -> [Int: [BookLink]] {
        var out: [Int: [BookLink]] = [:]
        for (page, links) in byBook[bookID] ?? [:] {
            if let number = Int(page) { out[number] = links }
        }
        return out
    }
}

/// Routes a tap on a link in a page's text to `onLink`. A page without links
/// is left exactly as it was.
struct BookLinkTaps: ViewModifier {
    let links: [BookLink]
    let onLink: ((BookLink) -> Void)?

    static let scheme = "dibooklink"

    func body(content: Content) -> some View {
        if links.isEmpty || onLink == nil {
            content
        } else {
            content
                .tint(DIColor.actionForeground)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == BookLinkTaps.scheme else { return .systemAction }
                    let raw = url.absoluteString.replacingOccurrences(of: "\(BookLinkTaps.scheme):", with: "")
                    if let index = Int(raw), links.indices.contains(index) {
                        onLink?(links[index])
                    }
                    return .handled
                })
        }
    }
}

/// A narration a book quotes, opened over the page: its collection at that
/// narration, as a search result opens it.
@MainActor
struct BookHadithSheet: View {
    /// `bookID|displayNumber|sourceSequence`.
    let canonicalID: String
    let dependencies: AppDependencies
    let appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var book: HadithBook?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if let book {
                    HadithBookView(
                        book: book,
                        repository: dependencies.hadithRepository,
                        appState: appState,
                        initialHadith: canonicalID
                    )
                } else if loaded {
                    DIEmptyState(systemImage: "text.book.closed", titleKey: "Hadith not found",
                                 messageKey: "This narration is not among the collections in the app.")
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .diScreenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            guard !loaded else { return }
            let bookID = canonicalID.split(separator: "|").first.map(String.init) ?? canonicalID
            let books = (try? await dependencies.hadithRepository.books()) ?? []
            book = books.first { $0.id == bookID }
            loaded = true
        }
    }
}
