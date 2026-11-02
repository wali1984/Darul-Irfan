import XCTest
import UIKit
import ImageIO
@testable import DarulIrfan

final class DailyPicturePreparationTests: XCTestCase {
    func testCorruptPictureCannotBecomeAnUpload() {
        XCTAssertNil(DailyPicturePreparation.jpeg(from: Data("invalid image".utf8)))
    }

    @MainActor
    func testLargePictureBecomesBoundedReadableJPEG() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4096, height: 2048), format: format).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4096, height: 2048))
        }
        let source = try XCTUnwrap(image.pngData())
        let prepared = await Task.detached { DailyPicturePreparation.jpeg(from: source) }.value
        let jpeg = try XCTUnwrap(prepared)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        XCTAssertEqual(pixels.width, 2048)
        XCTAssertEqual(pixels.height, 1024)
    }
}
