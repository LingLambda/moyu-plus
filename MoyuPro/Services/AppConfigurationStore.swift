import Foundation

struct AppConfiguration: Codable, Equatable, Sendable {
    var privacyProtectionCount = 0

    var normalized: Self {
        var copy = self
        copy.privacyProtectionCount = max(0, privacyProtectionCount)
        return copy
    }
}

/// Stores durable app data outside UserDefaults so it can be inspected and backed up as a file.
final class AppConfigurationStore: @unchecked Sendable {
    let fileURL: URL

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var configuration: AppConfiguration
    private(set) var lastErrorMessage: String?

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.configuration = Self.load(
            from: self.fileURL,
            legacyURL: fileURL == nil ? Self.legacySandboxFileURL(fileManager: fileManager) : nil,
            decoder: decoder
        )
        self.lastErrorMessage = nil
    }

    var privacyProtectionCount: Int { configuration.privacyProtectionCount }

    @discardableResult
    func recordPrivacyProtection() -> Int {
        configuration.privacyProtectionCount += 1
        save()
        return configuration.privacyProtectionCount
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(configuration.normalized)
            try data.write(to: fileURL, options: .atomic)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private static func load(
        from url: URL,
        legacyURL: URL?,
        decoder: JSONDecoder
    ) -> AppConfiguration {
        let sourceURL = FileManager.default.fileExists(atPath: url.path) ? url : legacyURL
        guard let sourceURL,
              let data = try? Data(contentsOf: sourceURL),
              let configuration = try? decoder.decode(AppConfiguration.self, from: data) else {
            return AppConfiguration()
        }
        return configuration.normalized
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("MoyuPro", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func legacySandboxFileURL(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent("com.ling.MoyuPro", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("MoyuPro", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}
