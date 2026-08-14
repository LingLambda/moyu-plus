import CoreGraphics
import Testing
@testable import MoyuPro

struct DetectionFilterTests {
    @Test func keepsOnlyConfidentPeopleAboveMinimumArea() {
        let filter = DetectionFilter(confidenceThreshold: 0.25, minimumAreaRatio: 0.01)
        let detections = [
            Detection(classID: 0, label: "person", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 0.2, height: 0.2)),
            Detection(classID: 0, label: "person", confidence: 0.2, boundingBox: CGRect(x: 0, y: 0, width: 0.2, height: 0.2)),
            Detection(classID: 0, label: "person", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 0.05, height: 0.05)),
            Detection(classID: 1, label: "bicycle", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 0.2, height: 0.2))
        ]

        #expect(filter.validPeople(in: detections).count == 1)
    }
}
