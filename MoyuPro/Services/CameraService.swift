@preconcurrency import AVFoundation
import CoreImage
import Foundation

struct CameraFrameResult: @unchecked Sendable {
    let image: CGImage?
    let snapshot: DetectionSnapshot
}

enum CameraServiceError: LocalizedError {
    case noCamera
    case selectedCameraMissing
    case cameraUnauthorized
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCamera: "未发现可用摄像头"
        case .selectedCameraMissing: "所选摄像头已断开"
        case .cameraUnauthorized: "摄像头未授权，请在系统设置 > 隐私与安全性 > 摄像头中允许大墨鱼访问"
        case .cannotAddInput: "无法连接所选摄像头"
        case .cannotAddOutput: "无法创建摄像头画面输出"
        }
    }
}

enum CameraServiceEvent: Sendable {
    case interrupted(String)
    case resumed
    case failed(String)
}

final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    typealias FrameHandler = @Sendable (CameraFrameResult) -> Void
    typealias EventHandler = @Sendable (CameraServiceEvent) -> Void

    private let queue = DispatchQueue(label: "com.ling.MoyuPro.camera", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var detector: YOLODetector?
    private var detectorLoadError: String?
    private var lastProcessedTime: CFTimeInterval = 0
    private var targetFPS = 2.0
    private var previewEnabled = true
    private var processedFrames = 0
    private var firstFrameTime: CFTimeInterval?
    private var frameHandler: FrameHandler?
    private var eventHandler: EventHandler?
    private var configuredDeviceID: String?
    private var shouldRun = false
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        do {
            detector = try YOLODetector()
        } catch {
            detectorLoadError = error.localizedDescription
        }
        registerSessionObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var modelError: String? { detectorLoadError }

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    static func availableDevices() -> [CameraDeviceDescriptor] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        )
        let preferredID = AVCaptureDevice.systemPreferredCamera?.uniqueID
        return discovery.devices.map {
            CameraDeviceDescriptor(
                id: $0.uniqueID,
                name: $0.localizedName,
                isSystemPreferred: $0.uniqueID == preferredID
            )
        }
    }

    func start(
        deviceID: String?,
        frameHandler: @escaping FrameHandler,
        eventHandler: @escaping EventHandler
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.frameHandler = frameHandler
            self.eventHandler = eventHandler
            self.shouldRun = true
            do {
                try self.configureIfNeeded(deviceID: deviceID)
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            } catch {
                self.shouldRun = false
                eventHandler(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = false
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.lastProcessedTime = 0
            self.firstFrameTime = nil
            self.processedFrames = 0
        }
    }

    func switchDevice(to deviceID: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            let wasRunning = self.session.isRunning
            if wasRunning { self.session.stopRunning() }
            self.clearConfiguration()
            do {
                try self.configureIfNeeded(deviceID: deviceID)
                if wasRunning { self.session.startRunning() }
            } catch {
                self.shouldRun = false
                self.eventHandler?(.failed(error.localizedDescription))
            }
        }
    }

    func setTargetFPS(_ fps: Double) {
        queue.async { [weak self] in
            self?.targetFPS = max(1, fps)
        }
    }

    func setPreviewEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            self?.previewEnabled = enabled
        }
    }

    private func configureIfNeeded(deviceID: String?) throws {
        if configuredDeviceID == deviceID, !session.inputs.isEmpty { return }
        clearConfiguration()

        guard Self.authorizationStatus() == .authorized else {
            throw CameraServiceError.cameraUnauthorized
        }

        let devices = Self.captureDevices()
        guard !devices.isEmpty else { throw CameraServiceError.noCamera }
        let device: AVCaptureDevice
        if let deviceID {
            guard let selected = devices.first(where: { $0.uniqueID == deviceID }) else {
                throw CameraServiceError.selectedCameraMissing
            }
            device = selected
        } else if let preferred = AVCaptureDevice.systemPreferredCamera {
            device = preferred
        } else {
            device = devices[0]
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraServiceError.cannotAddInput }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraServiceError.cannotAddOutput }
        session.addOutput(output)
        configuredDeviceID = device.uniqueID
    }

    private func clearConfiguration() {
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        configuredDeviceID = nil
    }

    private static func captureDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private func registerSessionObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            self.eventHandler?(.interrupted("摄像头采集被系统中断"))
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard self.shouldRun else { return }
                if !self.session.isRunning { self.session.startRunning() }
                self.eventHandler?(.resumed)
            }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
            self.queue.async {
                self.shouldRun = false
                self.eventHandler?(.failed(error?.localizedDescription ?? "摄像头运行失败"))
            }
        })
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        guard now - lastProcessedTime >= 1 / targetFPS,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        lastProcessedTime = now
        let start = CACurrentMediaTime()

        do {
            guard let detector else {
                throw YOLODetectorError.modelNotFound
            }
            let detections = try detector.detect(pixelBuffer: pixelBuffer)
            let inferenceMilliseconds = (CACurrentMediaTime() - start) * 1_000
            processedFrames += 1
            if firstFrameTime == nil { firstFrameTime = now }
            let elapsed = max(0.001, now - (firstFrameTime ?? now))
            let effectiveFPS = processedFrames > 1 ? Double(processedFrames - 1) / elapsed : 0
            let sourceSize = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            )
            let image = previewEnabled ? makeImage(from: pixelBuffer) : nil
            let snapshot = DetectionSnapshot(
                detections: detections,
                sourceSize: sourceSize,
                metrics: DetectionMetrics(
                    inferenceMilliseconds: inferenceMilliseconds,
                    effectiveFPS: effectiveFPS,
                    processedFrames: processedFrames
                )
            )
            frameHandler?(CameraFrameResult(image: image, snapshot: snapshot))
        } catch {
            shouldRun = false
            eventHandler?(.failed(error.localizedDescription))
        }
    }

    private func makeImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(image, from: image.extent)
    }
}
