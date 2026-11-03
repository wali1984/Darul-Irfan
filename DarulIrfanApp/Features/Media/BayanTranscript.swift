import Foundation
import Observation

// MARK: - Transcript

/// A bayan's timed transcript, as `GET /v1/transcripts/<mediaId>` serves it:
/// the spoken Urdu line by line, and the Qur'an, hadith and duas the Sheikh
/// recites in their source text with a reference. Arabic the pipeline could
/// not match to a source has no text: it is shown as "Arabic recitation",
/// never as Urdu transcription of Arabic.
struct BayanTranscript: Sendable, Equatable {
    enum Kind: String, Sendable {
        case speech, quran, hadith, dua, arabicUnverified
    }

    struct Line: Sendable, Equatable, Identifiable {
        /// Position in the transcript, from 0.
        var id: Int
        var start: Double
        var end: Double
        var kind: Kind
        /// Nil for an Arabic recitation marker.
        var text: String?
        /// "87:4" for the Qur'an; a hadith canonical id ("muslim|93|94") or a
        /// dua source ("hisn|2|2", "zikr:taawwudh", "book:<id>:<page>").
        var reference: String?
        /// A line the pipeline was unsure of: shown a little lighter.
        var isSuspect: Bool = false
    }

    var id: String
    var title: String
    var lines: [Line]

    enum DecodeError: Error { case empty }

    /// Reads the served JSON. Lines without a usable time are dropped; a
    /// source line without its reference, or an unknown kind without text,
    /// is shown as a recitation marker rather than as unchecked Arabic.
    static func decode(_ data: Data) throws -> BayanTranscript {
        let raw = try JSONDecoder().decode(RawDocument.self, from: data)
        var lines: [Line] = []
        for segment in raw.segments {
            guard let start = segment.s, start.isFinite, start >= 0 else { continue }
            let end = segment.e.flatMap { $0.isFinite && $0 >= start ? $0 : nil } ?? start
            let text = segment.t?.trimmingCharacters(in: .whitespacesAndNewlines)
            let reference = segment.ref?.trimmingCharacters(in: .whitespaces)
            var kind = Kind(rawValue: segment.kind ?? "") ?? .speech
            switch kind {
            case .quran:
                if QuranReference(reference) == nil { kind = .arabicUnverified }
            case .hadith, .dua:
                if (reference ?? "").isEmpty { kind = .arabicUnverified }
            case .speech, .arabicUnverified:
                break
            }
            if kind != .arabicUnverified, (text ?? "").isEmpty { continue }
            lines.append(Line(
                id: 0, start: start, end: end, kind: kind,
                text: kind == .arabicUnverified ? nil : text,
                reference: kind == .speech || kind == .arabicUnverified ? nil : reference,
                isSuspect: segment.q == true
            ))
        }
        let merged = mergingRecitationMarkers(lines.sorted { $0.start < $1.start })
        guard !merged.isEmpty else { throw DecodeError.empty }
        return BayanTranscript(id: raw.id ?? "", title: raw.title ?? "", lines: merged)
    }

    /// Consecutive "Arabic recitation" markers become one, from the first's
    /// start to the last's end. Ids are renumbered in order.
    static func mergingRecitationMarkers(_ lines: [Line]) -> [Line] {
        var result: [Line] = []
        for line in lines {
            if line.kind == .arabicUnverified, let last = result.last, last.kind == .arabicUnverified {
                result[result.count - 1].end = max(last.end, line.end)
                result[result.count - 1].isSuspect = last.isSuspect && line.isSuspect
            } else {
                result.append(line)
            }
        }
        for index in result.indices { result[index].id = index }
        return result
    }

    /// The line being spoken at `time`: the last that has started. Nil before
    /// the first line.
    static func activeIndex(in lines: [Line], at time: Double) -> Int? {
        guard time.isFinite, let first = lines.first, time >= first.start else { return nil }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].start <= time { low = middle } else { high = middle - 1 }
        }
        return low
    }

    func activeIndex(at time: Double) -> Int? { Self.activeIndex(in: lines, at: time) }

    /// The lines holding `query`, ignoring case and Arabic/Urdu diacritics.
    func lines(matching query: String) -> [Line] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return lines }
        return lines.filter { line in
            guard let text = line.text else { return false }
            return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// "1:05" or "1:02:09": whole seconds, never rounded up past the start.
    static func timeLabel(_ seconds: Double) -> String {
        let total = Int((seconds.isFinite ? max(0, seconds) : 0).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: Raw JSON

    private struct RawDocument: Decodable {
        var id: String?
        var title: String?
        var segments: [RawSegment]
    }

    private struct RawSegment: Decodable {
        var s: Double?
        var e: Double?
        var t: String?
        var kind: String?
        var ref: String?
        var q: Bool?

        enum CodingKeys: String, CodingKey { case s, e, t, kind, ref, q }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            s = try? container.decodeIfPresent(Double.self, forKey: .s)
            e = try? container.decodeIfPresent(Double.self, forKey: .e)
            t = try? container.decodeIfPresent(String.self, forKey: .t)
            kind = try? container.decodeIfPresent(String.self, forKey: .kind)
            ref = try? container.decodeIfPresent(String.self, forKey: .ref)
            if let flag = try? container.decodeIfPresent(Int.self, forKey: .q) {
                q = flag != 0
            } else {
                q = try? container.decodeIfPresent(Bool.self, forKey: .q)
            }
        }
    }
}

// MARK: - References

/// A Qur'an reference "S:A" (or "S:A-E"), within the mushaf's 114 surahs.
struct QuranReference: Equatable, Sendable {
    var surahNumber: Int
    var ayahNumber: Int

    init?(_ text: String?) {
        guard let text else { return nil }
        let parts = text.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let surah = Int(parts[0]), (1...114).contains(surah),
              let ayah = Int(parts[1].split(separator: "-").first ?? ""), (1...286).contains(ayah) else { return nil }
        self.surahNumber = surah
        self.ayahNumber = ayah
    }
}

/// The short source label beside a hadith or dua: the collection's title
/// ("Sahih Muslim", "Hisn al-Muslim"), the book's title for a dua quoted from
/// one of the Silsila's books, else plain "Hadith" or "Dua".
enum TranscriptSourceLabel {
    /// Titles by collection or book id, read from the bundled catalogues.
    struct Titles: Sendable {
        var collections: [String: (english: String, urdu: String)] = [:]
        var books: [String: (english: String, urdu: String?)] = [:]
    }

    /// The collection or book id a reference names, and whether it is a book.
    static func source(of reference: String) -> (id: String, isBook: Bool)? {
        if reference.hasPrefix("book:") {
            let id = reference.dropFirst("book:".count).split(separator: ":").first.map(String.init) ?? ""
            return id.isEmpty ? nil : (id, true)
        }
        if reference.contains("|") {
            let id = reference.split(separator: "|").first.map(String.init) ?? ""
            return id.isEmpty ? nil : (id, false)
        }
        return nil
    }

    /// The label for `line`, or nil when the generic "Hadith"/"Dua" should show.
    static func title(for line: BayanTranscript.Line, titles: Titles, urdu: Bool) -> String? {
        guard let reference = line.reference, let source = source(of: reference) else { return nil }
        if source.isBook {
            guard let book = titles.books[source.id] else { return nil }
            if urdu, let title = book.urdu, !title.isEmpty { return title }
            return book.english
        }
        guard let collection = titles.collections[source.id] else { return nil }
        return urdu ? collection.urdu : collection.english
    }

    /// Reads only the titles `transcript` needs. Off the main thread: the
    /// catalogues are bundled JSON.
    static func titles(for transcript: BayanTranscript) -> Titles {
        var collectionIDs = Set<String>()
        var bookIDs = Set<String>()
        for line in transcript.lines where line.kind == .hadith || line.kind == .dua {
            guard let reference = line.reference, let source = source(of: reference) else { continue }
            if source.isBook { bookIDs.insert(source.id) } else { collectionIDs.insert(source.id) }
        }
        var titles = Titles()
        if !collectionIDs.isEmpty, let catalog = SeedBundle.hadithCatalog() {
            for book in catalog.books where collectionIDs.contains(book.id) {
                titles.collections[book.id] = (book.titleEnglish, book.titleUrdu)
            }
        }
        if !bookIDs.isEmpty {
            for item in SeedBundle.libraryItems() where bookIDs.contains(item.id) {
                titles.books[item.id] = (item.title, item.titleUrdu)
            }
        }
        return titles
    }
}

// MARK: - Store

/// Fetches a bayan's transcript and keeps it on the phone, one file per
/// bayan under Application Support, so it opens offline once seen. A kept
/// copy older than a week is refreshed when the bayan is opened online.
enum BayanTranscriptStore {
    enum Outcome: Sendable {
        case found(Data)
        case missing
        case failed
    }

    static let refreshAfter: TimeInterval = 7 * 24 * 3600

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bayan-transcripts", isDirectory: true)
    }

    static func fileURL(for mediaItemID: String, directory: URL = BayanTranscriptStore.directory) -> URL? {
        guard isMediaID(mediaItemID) else { return nil }
        return directory.appendingPathComponent(mediaItemID).appendingPathExtension("json")
    }

    /// The route's id rule: a catalogue id, never a path.
    static func isMediaID(_ id: String) -> Bool {
        guard (1...160).contains(id.count), let first = id.unicodeScalars.first,
              ("a"..."z").contains(first) || ("0"..."9").contains(first) else { return false }
        return id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_" }
    }

    /// The kept copy and whether it is due a refresh.
    static func kept(_ mediaItemID: String, directory: URL = BayanTranscriptStore.directory, now: Date = Date()) -> (data: Data, stale: Bool)? {
        guard let file = fileURL(for: mediaItemID, directory: directory),
              let data = try? Data(contentsOf: file) else { return nil }
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        return (data, now.timeIntervalSince(modified) > refreshAfter)
    }

    static func keep(_ data: Data, for mediaItemID: String, directory: URL = BayanTranscriptStore.directory) {
        guard let file = fileURL(for: mediaItemID, directory: directory) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: [.atomic])
    }

    static func discard(_ mediaItemID: String, directory: URL = BayanTranscriptStore.directory) {
        guard let file = fileURL(for: mediaItemID, directory: directory) else { return }
        try? FileManager.default.removeItem(at: file)
    }

    static func fetch(_ mediaItemID: String) async -> Outcome {
        guard isMediaID(mediaItemID) else { return .missing }
        let url = OfficialPlatformConfiguration.baseURL.appendingPathComponent("v1/transcripts/\(mediaItemID)")
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200: return .found(data)
            case 404: return .missing
            default: return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Space the kept transcripts use, for Content & Storage.
    static func cacheSummary(directory: URL = BayanTranscriptStore.directory) -> (bytes: Int64, files: Int) {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        var bytes: Int64 = 0
        var count = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            bytes += Int64(values.fileSize ?? 0)
            count += 1
        }
        return (bytes, count)
    }

    /// Removes every kept transcript; returns how many would not go.
    static func clearCache(directory: URL = BayanTranscriptStore.directory) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var failed = 0
        for file in files {
            do { try FileManager.default.removeItem(at: file) } catch { failed += 1 }
        }
        return failed
    }
}

// MARK: - Model

/// The full player's transcript of the bayan playing. Its switch shows only
/// once there is a transcript to show.
@Observable
@MainActor
final class BayanTranscriptModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(BayanTranscript)
        /// This bayan has no transcript.
        case unavailable
        /// It could not be fetched, and none is kept.
        case failed
    }

    private(set) var state: State = .idle
    private(set) var titles = TranscriptSourceLabel.Titles()
    private var mediaItemID: String?
    private var generation = 0

    /// Bayans found without a transcript this session, not asked again for
    /// ten minutes.
    private static var missing: [String: Date] = [:]

    var transcript: BayanTranscript? {
        if case .loaded(let transcript) = state { return transcript }
        return nil
    }

    func load(mediaItemID: String?) async {
        generation += 1
        let current = generation
        self.mediaItemID = mediaItemID
        guard let mediaItemID, BayanTranscriptStore.isMediaID(mediaItemID) else {
            state = .idle
            return
        }
        // The last bayan's lines never show under the next one's title.
        if transcript?.id != mediaItemID { state = .loading }
        if let kept = await Task.detached(priority: .userInitiated, operation: { BayanTranscriptStore.kept(mediaItemID) }).value,
           let decoded = await Self.decoded(kept.data) {
            guard current == generation else { return }
            show(decoded)
            guard kept.stale else { return }
            if case .found(let data) = await BayanTranscriptStore.fetch(mediaItemID), let fresh = await Self.decoded(data) {
                BayanTranscriptStore.keep(data, for: mediaItemID)
                guard current == generation else { return }
                show(fresh)
            }
            return
        }
        if let since = Self.missing[mediaItemID], Date().timeIntervalSince(since) < 600 {
            state = .unavailable
            return
        }
        state = .loading
        let outcome = await BayanTranscriptStore.fetch(mediaItemID)
        guard current == generation else { return }
        switch outcome {
        case .found(let data):
            if let decoded = await Self.decoded(data) {
                guard current == generation else { return }
                BayanTranscriptStore.keep(data, for: mediaItemID)
                show(decoded)
            } else {
                state = .failed
            }
        case .missing:
            Self.missing[mediaItemID] = Date()
            state = .unavailable
        case .failed:
            state = .failed
        }
    }

    func retry() async {
        let id = mediaItemID
        mediaItemID = nil
        await load(mediaItemID: id)
    }

    private func show(_ value: (BayanTranscript, TranscriptSourceLabel.Titles)) {
        titles = value.1
        state = .loaded(value.0)
    }

    private static func decoded(_ data: Data) async -> (BayanTranscript, TranscriptSourceLabel.Titles)? {
        await Task.detached(priority: .userInitiated) { () -> (BayanTranscript, TranscriptSourceLabel.Titles)? in
            guard let transcript = try? BayanTranscript.decode(data) else { return nil }
            return (transcript, TranscriptSourceLabel.titles(for: transcript))
        }.value
    }
}
