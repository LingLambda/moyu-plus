import AppKit
@preconcurrency import AVFoundation
import SwiftUI

@main
struct MoyuProApp: App {
    @State private var model = AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Label("大墨鱼", systemImage: model.statusSymbolName)
        }
        .menuBarExtraStyle(.window)

        Window("大墨鱼", id: "dashboard") {
            DashboardView(model: model)
        }
        .defaultSize(width: 820, height: 620)
        .windowResizability(.contentMinSize)

    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindowController: NSWindowController?
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerSystemObservers()
        AppModel.shared.resumeSavedPreferenceIfNeeded()
        guard !AppModel.shared.onboardingComplete,
              !Self.launchedAsLoginItem else { return }
        DispatchQueue.main.async {
            self.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        distributedObservers.forEach(DistributedNotificationCenter.default().removeObserver)
        distributedObservers.removeAll()
    }

    func showOnboarding() {
        if let window = onboardingWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = OnboardingView(model: AppModel.shared) { [weak self] in
            self?.onboardingWindowController?.close()
            self?.onboardingWindowController = nil
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "欢迎使用大墨鱼"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 460))
        window.center()
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        onboardingWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication &&
            event.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem)?.booleanValue == true
    }

    private func registerSystemObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let suspendNames: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        let resumeNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]

        observers += suspendNames.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in AppModel.shared.suspendForSystemEvent() }
            }
        }
        observers += resumeNames.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in AppModel.shared.resumeAfterSystemEvent() }
            }
        }

        let deviceNames: [Notification.Name] = [
            AVCaptureDevice.wasConnectedNotification,
            AVCaptureDevice.wasDisconnectedNotification,
        ]
        observers += deviceNames.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in AppModel.shared.refreshDevices() }
            }
        }

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    await AppModel.shared.refreshPermissionStates()
                }
            }
        )

        distributedObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    AppModel.shared.observeAccessibilityChange()
                }
            }
        )
    }
}
