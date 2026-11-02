import XCTest
import PDFKit
import UIKit
@testable import DarulIrfan

@MainActor
final class PDFZoomControllerTests: XCTestCase {
    func testZoomBoundsFitAndCurrentPage() throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
        let data = renderer.pdfData { context in
            for _ in 0..<2 { context.beginPage() }
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        view.layoutIfNeeded()
        let controller = PDFZoomController()
        controller.view = view
        controller.fit()
        let fitted = view.scaleFactorForSizeToFit
        XCTAssertGreaterThan(fitted, 0)
        XCTAssertEqual(view.scaleFactor, fitted, accuracy: 0.001)
        let page = try XCTUnwrap(document.page(at: 1))
        view.go(to: page)
        controller.enlarge()
        XCTAssertGreaterThan(view.scaleFactor, fitted)
        XCTAssertTrue(view.currentPage === page)
        for _ in 0..<30 { controller.enlarge() }
        XCTAssertLessThanOrEqual(view.scaleFactor, fitted * 4 + 0.001)
        for _ in 0..<40 { controller.reduce() }
        XCTAssertEqual(view.scaleFactor, fitted, accuracy: 0.001)
        controller.enlarge()
        controller.fit()
        XCTAssertEqual(view.scaleFactor, fitted, accuracy: 0.001)
        XCTAssertTrue(view.autoScales)
    }

    func testControllerDoesNotRetainClosedReader() {
        let controller = PDFZoomController()
        autoreleasepool {
            let view = PDFView()
            controller.view = view
            XCTAssertNotNil(controller.view)
        }
        XCTAssertNil(controller.view)
        controller.enlarge()
        controller.reduce()
        controller.fit()
    }
}
