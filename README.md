# NagaController

[![GitHub stars](https://img.shields.io/github/stars/DParent10/NagaController?style=social)](https://github.com/DParent10/NagaController)

A macOS menu bar app to remap the 12 side buttons of the Razer Naga V2 Hyperspeed. Intercepts the default 1–0–=– key events and maps them to actions like key sequences, app launching, and macros. Displays battery level over Bluetooth and the supported HyperSpeed USB receiver.

**[⬇️ Download Latest Upstream Release (v0.2.3)](https://github.com/DParent10/NagaController/releases/latest)**

## Changelog / 更新日志

### 2026-11-23 · `zh-hans`

- 点击菜单栏图标即可速查当前配置的侧键、DPI 和滚轮绑定。
- 速查随配置更新，显示动作名称和实际快捷键。快捷键预设支持左、右 Command 同按。
- 点击桌面或其他 App 时，自动收起菜单栏速查。

### 2026-11-22 · `zh-hans`

- 缩小按键绑定页的侧键、DPI 和滚轮卡片，在页首显示电量。
- 新增 Naga V2 HyperSpeed 2.4 GHz USB 接收器的电量读取。应用启动时读取，之后约每分钟刷新，沿用已有的「输入监控」权限。
- 新增简体中文界面。

以上更新可通过[本分支源码构建](#build-from-source)获得。

## Features

- Remap Naga side buttons 1–12 to:
  - Key sequences
  - Launch applications
  - Simple macros
  - Profile switching
- Toggle remapping ON/OFF from the menu bar
- View the current button assignments directly in the menu bar popover
- Configure mappings in a dedicated window
- Test a mapping instantly from the editor, without pressing the physical button
- Battery percentage via Bluetooth (UUID 0x180F / 0x2A19) or the Naga V2 HyperSpeed USB receiver
- Launch at login, and an optional Dock icon (the app is menu-bar only by default)
- Notifies you in the app window when a newer release is available. This checks GitHub's releases API at most once a day; nothing is downloaded or sent beyond that request.
- Warns before importing a profile that runs shell commands
- Modern dark UI with Razer-green accents

## Requirements

- macOS 13.0 or later
- Razer Naga V2 Hyperspeed (other Naga models may work; device matching by vendor/product name is included)
- Bluetooth enabled when using Bluetooth battery reporting

## Installation

1. Download `NagaController-v0.2.3.dmg` from [Releases](https://github.com/DParent10/NagaController/releases/latest)
2. Open the DMG file
3. Drag `NagaController.app` to the Applications folder
4. Double-click `NagaController.app` to launch

### First run setup

See the [user guide](USER-GUIDE.md) for shortcuts, profile switching, Hypershift, permissions, and a tested DPI button setup.

1. Click the menu bar icon → turn ON "Enable remapping"
2. Click "Configure mappings…" to set actions for buttons 1–12

### Permissions

- **Accessibility**: System Settings → Privacy & Security → Accessibility → enable "NagaController"
- **Input Monitoring**: System Settings → Privacy & Security → Input Monitoring → enable "NagaController", then quit and reopen the app
- **Bluetooth battery reporting**: System Settings → Privacy & Security → Bluetooth → allow "NagaController"
- **Tip**: Always launch the same `.app` you granted permissions to (avoid running other binaries) so permissions persist

## Known limitations

- USB battery reporting currently supports the Naga V2 HyperSpeed receiver (`1532:00b4`).

## Supported Devices

- Razer Naga family, tested on: `Naga V2 Hyperspeed (Naga V2 HS)`
- Matching logic in `Sources/NagaController/HID/HIDListener.swift`:
  - Vendor IDs: `0x1532` (Razer) or `0x068e` (observed on some Naga V2 HS units)
  - OR product name contains `"naga"` (case-insensitive) as a fallback
- Regular keyboards are not remapped. Events are only blocked when a recent HID press from a matching Naga device is correlated with the event tap

## Troubleshooting

1. Grant Accessibility permissions (System Settings → Privacy & Security → Accessibility) and ensure the app is checked
2. Launch from Terminal with verbose tracing to see diagnostics (launch through `open`; running the binary directly makes macOS kill the app on its first Bluetooth access). Per-event logs only print when `NAGA_DEBUG` is set:
   ```bash
   open --env NAGA_DEBUG=1 --stdout /tmp/naga.log --stderr /tmp/naga.log /Applications/NagaController.app && tail -f /tmp/naga.log
   ```
3. Turn ON "Enable remapping" in the menu bar popover
4. Expected logs:
   - Startup:
     - `[Permissions] Accessibility trusted = true`
     - `[HID] Listener started. VERSION: ...` (if you see `IOHIDManagerOpen failed` instead, Input Monitoring is missing)
     - `[HID] DISCOVERY: [...] product=Naga V2 HS, vendor=0x68e, ...` (your device may vary)
     - `[EventTap] Starting with listenOnly=false` with no `CRITICAL` line after it
   - On side-button press:
     - `[HID] Mapped Keyboard press for button 1` followed by `[EventTap] Detected Naga button 1` (etc.)
   - On a paired wheel tilt or click:
     - `[Pointer] HID observed slot=15 ...` followed by `[Pointer] Suppressed native pan; performed slot=15`
5. If mouse buttons still type digits instead of your mapping:
   - Ensure remapping is enabled
   - Verify both Accessibility and Input Monitoring are granted, then quit and reopen the app
   - If the mouse was customised in Razer Synapse on Windows, reset its on-board profile there first (see the user guide)
   - Paste the relevant `[HID] DISCOVERY` and `[HID] Mapped` lines into an issue so we can whitelist your device if needed

## Battery

NagaController can show your mouse battery percentage when the mouse is connected over Bluetooth (BLE). It uses the standard Battery Service (UUID `0x180F`) and Battery Level characteristic (`0x2A19`).

For the Naga V2 HyperSpeed USB receiver (`1532:00b4`), NagaController also reads the percentage over USB using its existing Input Monitoring permission.

### How it works

- The app checks the USB receiver on launch and refreshes it roughly once a minute. A valid USB reading takes priority over Bluetooth.
- For Bluetooth, the app uses its Bluetooth permission and then:
  - Tries `retrieveConnectedPeripherals(withServices: [0x180F])` to attach to already-connected devices
  - Falls back to scanning for devices that advertise `0x180F` or whose name contains "Razer"/"Naga"
- Once connected, it reads Battery Level and subscribes for updates
- The battery percentage is displayed in the menu bar title and in the popover. At 20% or lower, the popover label turns red and a local notification is shown

### If you see "Battery: —"

- Wake the mouse and allow up to a minute for the next USB reading.
- For the Naga V2 HyperSpeed receiver, check Input Monitoring under System Settings → Privacy & Security.
- For Bluetooth, check the Bluetooth permission under System Settings → Privacy & Security.

## Build from source

```bash
# Build release app bundle
bash Scripts/build_app.sh

# Run the app
open ./NagaController.app
```

To open the button mapping window without taking keyboard focus on launch, run
`open -g -a ./NagaController.app --args --show-mappings-in-background`.

### Create DMG for distribution

```bash
cd dmg-assets
./setup-app-icon-and-dmg-simple.sh
```

This creates a signed and notarized DMG installer.

## Project Structure

- `Sources/NagaController/` — App source code (Swift + AppKit)
- `Resources/` — Info.plist, default profiles
- `Scripts/` — Build helper scripts
- `Tests/` — Unit tests
- `dmg-assets/` — Icon, background, and DMG creation script

## Feedback

Issues and logs are welcome. If your Naga isn't detected, please include the `[HID]` lines from the app's console output.

## License

See [LICENSE](LICENSE) for details.
