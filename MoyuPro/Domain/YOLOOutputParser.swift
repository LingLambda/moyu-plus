import CoreGraphics
import CoreML
import Foundation

enum YOLOOutputParser {
    static func detectionArray(from features: [MLFeatureValue]) -> MLMultiArray? {
        features.compactMap(\.multiArrayValue).first { array in
            array.shape.count == 3 && array.shape.last?.intValue == 6
        }
    }

    static func parse(
        values: [Double],
        rowCount: Int,
        sourceSize: CGSize,
        modelSize: CGSize = CGSize(width: 640, height: 640),
        labels: [Int: String] = [0: "person"],
        prefilterConfidence: Double = 0.01
    ) -> [Detection] {
        guard rowCount > 0, values.count >= rowCount * 6,
              sourceSize.width > 0, sourceSize.height > 0 else {
            return []
        }

        let gain = min(modelSize.width / sourceSize.width, modelSize.height / sourceSize.height)
        let padX = (modelSize.width - sourceSize.width * gain) / 2
        let padY = (modelSize.height - sourceSize.height * gain) / 2

        return (0..<rowCount).compactMap { row in
            let offset = row * 6
            let confidence = values[offset + 4]
            guard confidence >= prefilterConfidence else { return nil }

            let classID = Int(values[offset + 5].rounded())
            let x1 = (values[offset] - padX) / gain
            let y1 = (values[offset + 1] - padY) / gain
            let x2 = (values[offset + 2] - padX) / gain
            let y2 = (values[offset + 3] - padY) / gain

            let minX = max(0, min(1, x1 / sourceSize.width))
            let minY = max(0, min(1, y1 / sourceSize.height))
            let maxX = max(0, min(1, x2 / sourceSize.width))
            let maxY = max(0, min(1, y2 / sourceSize.height))
            guard maxX > minX, maxY > minY else { return nil }

            return Detection(
                classID: classID,
                label: labels[classID, default: "class \(classID)"],
                confidence: confidence,
                boundingBox: CGRect(
                    x: minX,
                    y: minY,
                    width: maxX - minX,
                    height: maxY - minY
                )
            )
        }
    }

    static func flattenedValues(from array: MLMultiArray) -> (values: [Double], rows: Int)? {
        guard array.shape.count == 3,
              array.shape[0].intValue == 1,
              array.shape[2].intValue == 6 else {
            return nil
        }

        let rows = array.shape[1].intValue
        let rowStride = array.strides[1].intValue
        let valueStride = array.strides[2].intValue
        var values = Array(repeating: 0.0, count: rows * 6)

        for row in 0..<rows {
            for column in 0..<6 {
                let index = row * rowStride + column * valueStride
                values[row * 6 + column] = array[index].doubleValue
            }
        }
        return (values, rows)
    }
}
