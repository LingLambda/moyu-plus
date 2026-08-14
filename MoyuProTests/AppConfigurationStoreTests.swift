import Foundation
import Testing
@testable import MoyuPro

struct AppConfigurationStoreTests {
    @Test func protectionCountSurvivesStoreReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoyuProTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstStore = AppConfigurationStore(fileURL: fileURL)
        #expect(firstStore.privacyProtectionCount == 0)
        #expect(firstStore.recordPrivacyProtection() == 1)
        #expect(firstStore.recordPrivacyProtection() == 2)

        let reloadedStore = AppConfigurationStore(fileURL: fileURL)
        #expect(reloadedStore.privacyProtectionCount == 2)
    }

    @Test func invalidConfigurationFallsBackToSafeDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoyuProTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)

        #expect(AppConfigurationStore(fileURL: fileURL).privacyProtectionCount == 0)
    }
}
