import CoreGraphics
import Testing
@testable import MoyuPro

struct YOLOOutputParserTests {
    @Test func parsesEndToEndRowsAndRemovesLetterboxPadding() throws {
        let values: [Double] = [
            64, 158, 320, 302, 0.91, 0,
            0, 0, 0, 0, 0, 0
        ]

        let detections = YOLOOutputParser.parse(
            values: values,
            rowCount: 2,
            sourceSize: CGSize(width: 1280, height: 720)
        )

        #expect(detections.count == 1)
        let box = try #require(detections.first?.boundingBox)
        #expect(abs(box.minX - 0.1) < 0.001)
        #expect(abs(box.minY - 0.05) < 0.001)
        #expect(abs(box.width - 0.4) < 0.001)
        #expect(abs(box.height - 0.4) < 0.001)
    }
}
