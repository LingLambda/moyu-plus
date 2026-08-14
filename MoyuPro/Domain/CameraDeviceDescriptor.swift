import Foundation

struct CameraDeviceDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isSystemPreferred: Bool
}
