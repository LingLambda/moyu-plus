import SwiftUI

struct DetectionPreviewView: View {
    let image: CGImage?
    let detections: [Detection]
    let isRunning: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    ForEach(detections) { detection in
                        detectionBox(detection, image: image, in: proxy.size)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: isRunning ? "video.fill" : "video.slash.fill")
                            .font(.system(size: 28))
                        Text(isRunning ? "等待摄像头画面" : "保护未运行")
                            .font(.headline)
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }
            }
            .clipped()
        }
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private func detectionBox(_ detection: Detection, image: CGImage, in size: CGSize) -> some View {
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (size.width - fittedSize.width) / 2,
            y: (size.height - fittedSize.height) / 2
        )
        let box = detection.boundingBox
        let width = box.width * fittedSize.width
        let height = box.height * fittedSize.height
        let centerX = origin.x + box.midX * fittedSize.width
        let centerY = origin.y + box.midY * fittedSize.height

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(.green, lineWidth: 2)
            Text("person \(Int(detection.confidence * 100))%")
                .font(.caption2.monospacedDigit().bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.green)
                .foregroundStyle(.black)
        }
        .frame(width: max(1, width), height: max(1, height))
        .position(x: centerX, y: centerY)
    }
}
