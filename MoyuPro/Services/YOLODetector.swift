@preconcurrency import CoreML
@preconcurrency import Vision
import CoreGraphics
import Foundation
import ImageIO

enum YOLODetectorError: LocalizedError {
    case modelNotFound
    case unsupportedOutput

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            "应用包中未找到 YOLO26 Core ML 模型"
        case .unsupportedOutput:
            "YOLO26 模型输出格式不受支持"
        }
    }
}

final class YOLODetector: @unchecked Sendable {
    static let bundledModelNames = ["yolo26n", "yolo26n_int8", "yolo26s"]

    private let model: VNCoreMLModel
    private let labels: [Int: String]

    init(bundle: Bundle = .main) throws {
        guard let modelURL = Self.findModelURL(in: bundle) else {
            throw YOLODetectorError.modelNotFound
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let mlModel = try MLModel(contentsOf: modelURL, configuration: configuration)
        model = try VNCoreMLModel(for: mlModel)
        labels = Self.parseLabels(from: mlModel.modelDescription.metadata)
    }

    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [Detection] {
        var outputArray: MLMultiArray?
        var requestError: Error?
        let request = VNCoreMLRequest(model: model) { request, error in
            requestError = error
            let values = (request.results ?? [])
                .compactMap { $0 as? VNCoreMLFeatureValueObservation }
                .map(\.featureValue)
            outputArray = YOLOOutputParser.detectionArray(from: values)
        }
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        try handler.perform([request])
        if let requestError { throw requestError }
        guard let outputArray,
              let flattened = YOLOOutputParser.flattenedValues(from: outputArray) else {
            throw YOLODetectorError.unsupportedOutput
        }

        let sourceSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        return YOLOOutputParser.parse(
            values: flattened.values,
            rowCount: flattened.rows,
            sourceSize: sourceSize,
            labels: labels
        )
    }

    private static func findModelURL(in bundle: Bundle) -> URL? {
        for name in bundledModelNames {
            if let url = bundle.url(forResource: name, withExtension: "mlmodelc") {
                return url
            }
        }
        return bundle.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil)?.first
    }

    private static func parseLabels(from metadata: [MLModelMetadataKey: Any]) -> [Int: String] {
        guard let creatorDefined = metadata[.creatorDefinedKey] as? [String: String],
              let names = creatorDefined["names"] else {
            return [0: "person"]
        }

        let pattern = #"(\d+)\s*:\s*['\"]([^'\"]+)['\"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [0: "person"]
        }
        let range = NSRange(names.startIndex..., in: names)
        var parsed: [Int: String] = [:]
        regex.enumerateMatches(in: names, range: range) { match, _, _ in
            guard let match,
                  let keyRange = Range(match.range(at: 1), in: names),
                  let valueRange = Range(match.range(at: 2), in: names),
                  let key = Int(names[keyRange]) else { return }
            parsed[key] = String(names[valueRange])
        }
        return parsed.isEmpty ? [0: "person"] : parsed
    }
}
