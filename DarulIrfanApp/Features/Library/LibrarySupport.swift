import Foundation
import SwiftUI

// Shared value types and small display helpers for the Library feature.
// Everything here is UI-support only; domain models live in Models/.

// MARK: - Navigation

/// Navigation destinations within the Library tab's NavigationStack.
enum LibraryRoute: Hashable {
    case category(ContentCategory)
    case item(id: String)
    case favorites
    case pdf(url: URL, title: String)
}

// MARK: - Category grouping

/// Display grouping of the library taxonomy for the Library home screen.
struct LibraryCategoryGroup: Identifiable, Sendable {
    let id: String
    /// Natural-English title, resolved through the String Catalog at display time.
    let title: String
    let systemImage: String
    let categories: [ContentCategory]

    static let groups: [LibraryCategoryGroup] = [
        LibraryCategoryGroup(
            id: "about",
            title: "About",
            systemImage: "info.circle",
            categories: [.aboutSilsila, .sheikhAbdulQadeerAwan, .sheikhMuhammadAkramAwan, .shajra]
        ),
        LibraryCategoryGroup(
            id: "teachings",
            title: "Teachings",
            systemImage: "text.book.closed",
            categories: [.tasawwuf, .tazkiyahNafs, .zikrAllah, .methodOfZikr, .baiat]
        ),
        LibraryCategoryGroup(
            id: "publications",
            title: "Publications",
            systemImage: "books.vertical",
            categories: [.books, .booklets, .articles, .sufiPoetry, .alMurshidMagazine, .trainingCourses, .importantDocuments]
        ),
        LibraryCategoryGroup(
            id: "news",
            title: "News",
            systemImage: "megaphone",
            categories: [.announcements, .pressReleases, .featureArticles, .aqwalESheikh]
        )
    ]

    /// The three categories surfaced as featured cards on the Library home.
    static let featuredCategories: Set<ContentCategory> = [
        .aboutSilsila, .sheikhAbdulQadeerAwan, .sheikhMuhammadAkramAwan
    ]
}

// MARK: - Display names

extension ContentType {
    /// Natural-English display name; wrap in LocalizedStringKey when shown as
    /// localizable text.
    var libraryDisplayName: String {
        switch self {
        case .article: return "Article"
        case .book: return "Book"
        case .booklet: return "Booklet"
        case .magazine: return "Magazine"
        case .document: return "Document"
        case .announcement: return "Announcement"
        case .pressRelease: return "Press Release"
        case .poetry: return "Poetry"
        case .page: return "Page"
        }
    }
}

extension ContentCategory {
    /// SF Symbol representing this category in lists.
    var librarySymbol: String {
        switch self {
        case .aboutSilsila: return "book.closed"
        case .sheikhAbdulQadeerAwan: return "person.crop.circle"
        case .sheikhMuhammadAkramAwan: return "person.crop.circle"
        case .shajra: return "arrow.triangle.branch"
        case .tasawwuf: return "sparkles"
        case .tazkiyahNafs: return "heart"
        case .zikrAllah: return "moon.stars"
        case .methodOfZikr: return "list.bullet.rectangle"
        case .baiat: return "checkmark.seal"
        case .articles: return "doc.text"
        case .books: return "books.vertical"
        case .booklets: return "book"
        case .sufiPoetry: return "text.quote"
        case .trainingCourses: return "graduationcap"
        case .importantDocuments: return "doc.on.doc"
        case .alMurshidMagazine: return "magazine"
        case .pressReleases: return "newspaper"
        case .announcements: return "megaphone"
        case .featureArticles: return "doc.richtext"
        case .aqwalESheikh: return "quote.bubble"
        }
    }
}

// MARK: - Premium accents & medallions

extension ContentType {
    /// SF Symbol for this item type, shown inside the item's gradient medallion.
    var libraryIcon: String {
        switch self {
        case .article: return "doc.text"
        case .book: return "book.closed"
        case .booklet: return "book"
        case .magazine: return "magazine"
        case .document: return "doc.on.doc"
        case .announcement: return "megaphone"
        case .pressRelease: return "newspaper"
        case .poetry: return "text.quote"
        case .page: return "doc.richtext"
        }
    }

    /// Books, booklets, and magazines are the collection's treasures — they take
    /// the gold treatment so they read as special alongside articles and notices.
    var isFeaturedPublication: Bool {
        switch self {
        case .book, .booklet, .magazine: return true
        default: return false
        }
    }

    /// Accent used for this type's pill badge and card glow.
    var libraryAccent: Color {
        isFeaturedPublication ? DIColor.accent : DIColor.primary
    }
}

extension ContentCategory {
    /// Publication-heavy sections (books, booklets, magazine, documents, courses,
    /// poetry) carry the gold accent so the reading collections feel special;
    /// teachings and about-pages keep the emerald brand tone.
    var isPublicationCategory: Bool {
        switch self {
        case .books, .booklets, .alMurshidMagazine, .importantDocuments, .trainingCourses, .sufiPoetry:
            return true
        default:
            return false
        }
    }

    /// Accent used for this category's medallion, badge, and card glow.
    var libraryAccent: Color {
        isPublicationCategory ? DIColor.accent : DIColor.primary
    }
}

/// A gradient-filled circular icon medallion — emerald for standard items,
/// gilded gold for the collection's featured publications. The living visual
/// anchor of every Library card.
struct LibraryMedallion: View {
    let systemImage: String
    var isSpecial: Bool = false
    var diameter: CGFloat = 46
    /// Slow breathing halo — used on the sparser home cards, off for long lists.
    var breathing: Bool = false

    var body: some View {
        let glowColor = (isSpecial ? DIColor.accent : DIColor.primary).opacity(0.55)
        let core = ZStack {
            Circle()
                .fill(isSpecial ? DIGradient.goldSheen : DIGradient.emerald)
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(isSpecial ? DIColor.primaryDeep : DIColor.onPrimary)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)

        return Group {
            if breathing {
                core.diBreathingGlow(color: glowColor, maxRadius: 7)
            } else {
                core
            }
        }
    }
}

/// Display names for the BCP-47 language codes used by content items.
enum LibraryLanguage {
    static func displayName(forCode code: String) -> String {
        switch code.lowercased() {
        case "en": return "English"
        case "ur": return "Urdu"
        case "ar": return "Arabic"
        case "pa": return "Punjabi"
        default: return code.uppercased()
        }
    }
}

// MARK: - File names

enum LibraryFileName {
    /// Human-readable file name derived from a remote URL string.
    static func displayName(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        let raw = url.lastPathComponent
        let decoded = raw.removingPercentEncoding ?? raw
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? urlString : trimmed
    }
}

// MARK: - HTML → plain text

/// Conservative HTML-to-plain-text conversion for the native article reader.
/// We deliberately avoid NSAttributedString's HTML importer (WebKit-backed,
/// main-thread-bound, and heavy); a tag-stripping pass into paragraphs is
/// predictable and fast for the site's simple server-rendered markup.
enum LibraryHTMLText {
    static func plainText(fromHTML html: String) -> String {
        var text = html
        // Remove non-content blocks entirely.
        text = text.replacingOccurrences(
            of: "<script[\\s\\S]*?</script>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<style[\\s\\S]*?</style>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: " ",
            options: .regularExpression
        )
        // Turn line breaks and block-level boundaries into newlines.
        text = text.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "</(p|div|h1|h2|h3|h4|h5|h6|li|tr|blockquote|section|article)>",
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        // Strip every remaining tag.
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(in: text)
    }

    /// Splits plain text into trimmed, non-empty paragraphs for rendering.
    static func paragraphs(from plainText: String) -> [String] {
        plainText
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func decodeEntities(in input: String) -> String {
        var text = input
        // Ordered so that "&amp;" is decoded last and never double-decodes.
        let namedEntities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&rsquo;", "\u{2019}"),
            ("&lsquo;", "\u{2018}"),
            ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}"),
            ("&ndash;", "\u{2013}"),
            ("&mdash;", "\u{2014}"),
            ("&hellip;", "\u{2026}"),
            ("&amp;", "&")
        ]
        for (entity, replacement) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        // Decode numeric character references like &#1601; (Arabic/Urdu text).
        while let range = text.range(of: "&#[0-9]{1,7};", options: .regularExpression) {
            let digits = String(text[range].dropFirst(2).dropLast(1))
            if let value = UInt32(digits), let scalar = Unicode.Scalar(value) {
                text.replaceSubrange(range, with: String(Character(scalar)))
            } else {
                text.replaceSubrange(range, with: " ")
            }
        }
        return text
    }
}
