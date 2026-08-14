import AppKit
import Foundation
import OSLog

@MainActor
final class DiagnosticsLog {
    static let fileURL = applicationSupportDirectory
        .appendingPathComponent("diagnostics.log")

    private static let applicationSupportDirectory: URL = {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        return baseURL.appendingPathComponent("MoyuPro", isDirectory: true)
    }()

    private let logger: Logger
    private let category: String

    init(category: String) {
        self.category = category
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.ling.MoyuPro", category: category)
    }

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        append(level: "NOTICE", message: message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append(level: "ERROR", message: message)
    }

    func revealInFinder() {
        ensureFileExists()
        NSWorkspace.shared.activateFileViewerSelecting([Self.fileURL])
    }

    private func append(level: String, message: String) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: Self.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
            rotateIfNeeded(fileManager: fileManager)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(timestamp) [\(level)] [\(category)] \(message)\n"
            let data = Data(line.utf8)
            if fileManager.fileExists(atPath: Self.fileURL.path) {
                let handle = try FileHandle(forWritingTo: Self.fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: Self.fileURL, options: .atomic)
            }
        } catch {
            logger.error("Failed to write diagnostics file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureFileExists() {
        guard !FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        append(level: "NOTICE", message: "Diagnostics log created")
    }

    private func rotateIfNeeded(fileManager: FileManager) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: Self.fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 2_000_000 else { return }
        let archivedURL = Self.fileURL.deletingLastPathComponent()
            .appendingPathComponent("diagnostics.previous.log")
        try? fileManager.removeItem(at: archivedURL)
        try? fileManager.moveItem(at: Self.fileURL, to: archivedURL)
    }
}
