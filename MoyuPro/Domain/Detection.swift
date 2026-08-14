import CoreGraphics
import Foundation

struct Detection: Identifiable, Equatable, Sendable {
    let id: UUID
    let classID: Int
    let label: String
    let confidence: Double
    let boundingBox: CGRect

    init(
        id: UUID = UUID(),
        classID: Int,
        label: String,
        confidence: Double,
        boundingBox: CGRect
    ) {
        self.id = id
        self.classID = classID
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
    }

    var areaRatio: Double {
        max(0, boundingBox.width) * max(0, boundingBox.height)
    }
}

struct DetectionMetrics: Equatable, Sendable {
    var inferenceMilliseconds: Double = 0
    var effectiveFPS: Double = 0
    var processedFrames: Int = 0
}

struct DetectionSnapshot: Equatable, Sendable {
    var detections: [Detection] = []
    var sourceSize: CGSize = .zero
    var metrics = DetectionMetrics()
}
