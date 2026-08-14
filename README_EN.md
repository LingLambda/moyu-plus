# Moyu Pro

English | [简体中文](README.md)

Moyu Pro is a local-only macOS menu bar privacy utility. It uses the camera and Core ML to detect generic person candidates. When the configured person threshold is sustained, it can switch to selected windows or apps and send a customizable local notification.

Camera frames are processed only in memory. They are not uploaded or recorded, and the app does not perform face or identity recognition.

> [!IMPORTANT]
> Moyu Pro only provides an environmental change signal. It does not replace a door lock, screen lock, access control, or any other security measure, and it must not be used to monitor other people.

## Features

- On-device `person` candidate detection with Core ML
- Configurable trigger count, recovery count, recovery delay, confidence, and minimum target area
- Manual recovery after a trigger, or automatic recovery after the person count drops
- Window 1, Window 2, App 1, and App 2 can be configured independently and reordered
- Window matching supports automatic ID-first, strict window ID, and exact-title modes
- Exact windows are limited to the current Space; app targets can be launched or activated across Spaces
- Custom local notifications with an independent test action
- Optional live preview, camera selection, and launch at login
- Camera capture and model inference stop while protection is paused

## Requirements

- macOS 14.0 or later
- Xcode 26 or a compatible version for source builds
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) when regenerating the Xcode project
- `uv` and Python 3.12 only for model export and benchmarking

## Installation

Download the DMG from the releases page, drag Moyu Pro into Applications, and launch it from there. Window switching requires a non-sandboxed build so the app can access the macOS Accessibility Server. Keeping a stable installation path reduces the chance that macOS requests permissions again after an update.

If this repository does not have packaged releases yet, build it from source:

```bash
xcodegen generate
xcodebuild \
  -project MoyuPro.xcodeproj \
  -scheme MoyuPro \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

The app is written to Xcode DerivedData. Run `tools/package_debug_dmg.sh` to create a non-sandboxed ad-hoc debug DMG with Hardened Runtime camera access for local diagnosis. Distribution builds should use a stable bundle identifier and a Developer ID signature. macOS may treat separately built or ad-hoc signed copies as different Camera or Accessibility clients.

## Usage

1. Allow camera and notification access during first-run setup.
2. Enable window switching under Trigger Actions.
3. Select Open System Settings and allow the current Moyu Pro build in System Settings.
4. Return to the app. Permission and window discovery refresh automatically; Refresh Windows is also available.
5. Configure Window 1, Window 2, App 1, and App 2; set their priority, then run Test Switch.
6. Adjust the detection rules and enable protection.

Minimized windows and windows in another Space are excluded. The default automatic mode prefers the window ID, so title changes remain trackable while the window lives; it falls back to the title after a window rebuild or app relaunch. Strict-ID mode requires reselection after a rebuild, while title mode requires reselection after a title change. App targets do not depend on window titles.

## Development

```text
MoyuPro/
├── App/        Lifecycle and UI state orchestration
├── Domain/     Detection rules, state machines, window targets, and pure logic
├── Services/   Camera, Core ML, notifications, login items, and window APIs
├── UI/         Menu bar, onboarding, dashboard, and preview
└── Support/    Info.plist and entitlements
MoyuProTests/   Swift Testing unit tests
Models/         Core ML model resources
tools/          App icon and model tooling
```

Run the complete test suite:

```bash
xcodebuild \
  -project MoyuPro.xcodeproj \
  -scheme MoyuPro \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```

GitHub Actions builds and tests on macOS for every push and pull request. Publish a GitHub Release with a `v*` tag such as `v0.1.0`, or run the Release workflow manually, to build and upload the universal macOS DMG and its SHA-256 checksum. The current pipeline uses ad-hoc signing and is not notarized; a Developer ID identity is still required for formal cross-Mac distribution.

The project uses Swift 6, SwiftUI, Observation, AVFoundation, Vision/Core ML, the Accessibility API, and Core Graphics. Pure-logic tests cover window matching, the risk state machine, detection filtering, model output parsing, and lifecycle generations.

## Model

The app currently embeds a `YOLO26s FP16` Core ML model. See [`tools/model_benchmark/README.md`](tools/model_benchmark/README.md) for export and benchmarking instructions and [`tools/model_benchmark/MODEL_SELECTION.md`](tools/model_benchmark/MODEL_SELECTION.md) for the selection notes. Static benchmarks do not replace validation with real entry angles, occlusion, low light, backlight, and background movement.

Ultralytics models and tools remain subject to their respective licenses. Review those terms before distributing a modified model or app.

## Permissions

| Permission | Purpose | Without access |
| --- | --- | --- |
| Camera | Detect person candidates in memory | Protection cannot be enabled |
| Notifications | Send a customized local alert | Detection and window actions continue |
| Accessibility | Enumerate, focus, and raise exact windows | Notifications and App 1/App 2 remain available |
| Login item | Start the menu bar app after login | Only automatic startup is affected |

- Distribution builds do not enable App Sandbox; this is required for access to the Accessibility Server.
- Hardened Runtime builds retain the camera entitlement; the user must still grant Camera access in System Settings.

## Contributing

Keep module boundaries explicit, add tests for pure logic and edge cases, and run the full `xcodebuild test` command before submitting a change. Camera, Accessibility, signing, and Sandbox changes also require manual validation in a real app bundle because unit tests cannot emulate macOS TCC.

## License

Moyu Pro is licensed under the [GNU AGPL-3.0](LICENSE).

## Acknowledgements

- [moyu](https://github.com/x7722/moyu)
- [Ultralytics](https://github.com/ultralytics/ultralytics)
