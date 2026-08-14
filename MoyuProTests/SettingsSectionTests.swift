import Testing
@testable import MoyuPro

struct SettingsSectionTests {
    @Test func exposesEverySidebarDestination() {
        #expect(SettingsSection.allCases == [
            .triggerActions,
            .monitoringAndCamera,
            .detectionRules,
            .startupAndPermissions,
            .privacy,
        ])
        #expect(SettingsSection.defaultSection == .triggerActions)
        #expect(SettingsSection.normalized(nil) == .triggerActions)
        #expect(SettingsSection.normalized(.privacy) == .privacy)
    }

    @Test func sidebarMetadataIsUniqueAndNonempty() {
        let titles = SettingsSection.allCases.map(\.title)
        let symbols = SettingsSection.allCases.map(\.symbolName)

        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(symbols.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == SettingsSection.allCases.count)
        #expect(Set(symbols).count == SettingsSection.allCases.count)
    }
}
