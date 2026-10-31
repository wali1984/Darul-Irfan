import XCTest
@testable import DarulIrfan

final class MethodGuideTests: XCTestCase {
    func testEnglishInstructionsPreserveCompleteSourceOrder() throws {
        let guide = try XCTUnwrap(MethodGuide.load())
        let source = try XCTUnwrap(SeedBundle.libraryItem(id: "page-method-of-zikr")?.bodyPlainText)
        XCTAssertEqual(guide.en.map(\.text).joined(separator: "\n\n"), source)
    }

    func testUrduHasItsOwnRecitationsInstructionsAndConclusion() throws {
        let sections = try XCTUnwrap(MethodGuide.load()).ur
        XCTAssertEqual(sections.filter { $0.kind == "arabic" }.map(\.id),
                       ["tasbih", "istighfar", "shahadah", "taawwudh", "basmalah"])
        XCTAssertLessThan(try XCTUnwrap(sections.firstIndex { $0.id == "basmalah" }),
                          try XCTUnwrap(sections.firstIndex { $0.id == "latifa-1" }))
        XCTAssertEqual(sections.last?.id, "conclusion")
        XCTAssertEqual(Set(sections.map(\.id)).count, sections.count)
        XCTAssertTrue(sections.allSatisfy { !$0.text.isEmpty && $0.text.range(of: "[A-Za-z]", options: .regularExpression) == nil })
        XCTAssertTrue(sections.last?.text.contains("شجرہ") == true)
    }
}
