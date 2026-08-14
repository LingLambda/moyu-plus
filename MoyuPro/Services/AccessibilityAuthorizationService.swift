import ApplicationServices
import AppKit
import Foundation

@MainActor
final class AccessibilityAuthorizationService {
    private let diagnostics = DiagnosticsLog(category: "Accessibility")
    private let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    var isAuthorized: Bool {
        // Do not cache this value: TCC can change while the app is running.
        let trusted = AXIsProcessTrustedWithOptions(nil)
        return trusted
    }

    func requestAccess() -> Bool {
        // macOS owns the authorization list. Opening the official settings page is more reliable
        // than depending on the optional system prompt, especially for sandboxed apps.
        let authorized = isAuthorized
        diagnostics.notice("Accessibility access requested: trusted=\(authorized)")
        if !authorized, let settingsURL {
            let opened = NSWorkspace.shared.open(settingsURL)
            diagnostics.notice("Opened Accessibility settings: success=\(opened)")
        }
        return authorized
    }

    func openSettings() {
        guard let settingsURL else { return }
        let opened = NSWorkspace.shared.open(settingsURL)
        diagnostics.notice("Opened Accessibility settings: success=\(opened)")
    }
}
