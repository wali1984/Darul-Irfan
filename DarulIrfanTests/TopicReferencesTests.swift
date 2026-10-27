import XCTest
@testable import DarulIrfan

/// Every topic carries a full set of Qur'an and hadith references, built by
/// Tools/Library/build_topic_references.py, and every reference is readable.
final class TopicReferencesTests: XCTestCase {

    func testEveryTopicHasAyatAndHadith() throws {
        let topics = SeedBundle.topics()
        try XCTSkipIf(topics.isEmpty, "SeedData resources are not visible to this test host")
        for topic in topics {
            XCTAssertGreaterThanOrEqual(topic.ayahRefs.count, 7, "\(topic.id) has too few ayat")
            XCTAssertGreaterThanOrEqual(topic.hadithRefs?.count ?? 0, 6, "\(topic.id) has too few hadith")
            for ref in topic.ayahRefs {
                XCTAssertNotNil(AyahRef(ref), "\(topic.id): unreadable ayah reference \(ref)")
            }
            for ref in topic.hadithRefs ?? [] {
                XCTAssertEqual(ref.split(separator: "|").count, 3, "\(topic.id): unreadable hadith reference \(ref)")
            }
        }
    }

    /// An older topics file without hadith still decodes.
    func testTopicWithoutHadithDecodes() throws {
        let json = #"[{"id":"x","nameEnglish":"X","systemIcon":"star","searchTerms":["x"],"ayahRefs":["1:1"]}]"#
        let topics = try JSONDecoder().decode([Topic].self, from: Data(json.utf8))
        XCTAssertNil(topics.first?.hadithRefs)
    }
}
