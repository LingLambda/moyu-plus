import Foundation

struct DetectionFilter: Equatable, Sendable {
    var confidenceThreshold: Double = 0.25
    var minimumAreaRatio: Double = 0.012

    func validPeople(in detections: [Detection]) -> [Detection] {
        detections.filter {
            $0.classID == 0 &&
                $0.confidence >= confidenceThreshold &&
                $0.areaRatio >= minimumAreaRatio
        }
    }
}
