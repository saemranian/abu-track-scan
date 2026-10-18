# Walkthrough: Multi-Component Version Control, Abu Clock Integration & Minimalist Studio UI/UX Redesign

This document provides the complete walkthrough of:
1. **Multi-Component 4-Part Decimal Rollover Version Control System** (`win`, `ios`, `ue`) and its audit documentation.
2. **Abu Clock Sub-Microsecond Synchronization Integration (Phases 0–6)** (`ios v0.0.7.1`–`v0.0.7.6`, `win v0.1.0.2`–`v0.1.0.4`, `ue v0.0.0.1`–`v0.0.0.2`).
3. **Minimalist Studio UI/UX Redesign, Iconography & Contextual Guides (Phases 1–4)** (`ios v0.0.7.7`–`v0.0.7.9`, `win v0.1.0.5`–`v0.1.0.8`, `ue v0.0.0.3`).

---

## 1. Multi-Component Version Control System & Documentation

> [!IMPORTANT]
> **How Version Control Docs Are Structured**:
> Every single code edit to the **Windows Workstation (`win`)**, **iOS App (`ios`)**, or **Unreal Engine 5 Plugin (`ue`)** is tracked independently using a deterministic **base-10 4-part decimal rollover scheme** (`vA.B.C.D`, where `.9` rolls over to `.1.0`, e.g., `v0.1.0.9` -> `v0.1.1.0`) and logged in both `VERSION_CHANGELOG.md` and `app_versions.json`, plus this permanent walkthrough in `docs/WALKTHROUGH_ABU_CLOCK_AND_VERSIONING.md`.

### 1.1 Automated Version Controller (`build_version_tracker.py`)
- **CLI Usage**:
  ```bash
  python build_version_tracker.py --target <win|ios|ue> --task "<description of implemented task>"
  ```
- **Current Component Versions**:
  - **iOS App (`ios`)**: `v0.0.7.9` (Build `#103`) — `Sources/Version.swift` & `project.yml`
  - **Windows Workstation (`win`)**: `v0.1.0.9` (Build `#102`) — `DesktopSync/version_info.py` & `dist/abu_track_desktop.exe`
  - **UE5 Plugin (`ue`)**: `v0.0.0.3` (Build `#3`) — `LiveLinkAbuTrack.uplugin` & `LiveLinkAbuTrackVersion.h`

### 1.2 Complete Commit & Version Audit Table

| Git Commit | Component | Version | Build | Implemented Task Summary |
| :--- | :--- | :--- | :---: | :--- |
| `7dc78e0` | **All (`win` / `ios` / `ue`)** | Baseline | `#94` | **Phase 0**: Multi-component 4-part decimal rollover version controller (`build_version_tracker.py`, `app_versions.json`, `VERSION_CHANGELOG.md`, `LiveLinkAbuTrackVersion.h`). |
| `dd680dc` | **iOS App (`ios`)** | `v0.0.7.1` | `#95` | **Phase 1.1**: Embed `AbuClockKit.swift` 2-state Kalman PLL on `mach_continuous_time()`, UDP `50320` Stratum-1 SNTP + `ABU_ECO_V1` auto-discovery, and UDP `50319` `SCHEDULE_CAPTURE_AT` listener. |
| `da3b58f` | **iOS App (`ios`)** | `v0.0.7.2` | `#96` | **Phase 1.2**: Add `AbuClockSlateView.swift` Digital Clapper Slate with `Frame-00` optical flash marker and live SMPTE Timecode HUD bar on Dashboard. |
| `5b2dcbb` | **iOS App (`ios`)** | `v0.0.7.3` | `#97` | **Phase 2.1–2.2**: Upgrade `CameraManager.swift` with optical exposure-midpoint TAI/SMPTE timestamping, deterministic filenames (`IMG_YYYYMMDD_HHMMSS_FF_<tai_ns>.jpg`), and future-time barrier shutter firing. |
| `6d07105` | **iOS App (`ios`)** | `v0.0.7.4` | `#98` | **Phase 2.3–2.4**: Sync LiDAR depth snapshots (`.ply`/`.pts`) and 60Hz CSV telemetry with TAI/SMPTE timecode in `MotionManager.swift`; add `.abuscan.json`, COLMAP `images.txt`, and SLERP + Slate Flash Offset solver in `PhotoSyncManager.swift`. |
| `fc3303d` | **iOS App (`ios`)** | `v0.0.7.5` | `#99` | **Phase 3.1**: Upgrade `UDPStreamingManager.swift` with AbuClock SMPTE/TAI fields in LiveLink JSON, 41-byte `0xD2` FreeD-TC, and OpenTrackIO `PTP_SMPTE_ST2059_2` timing block. |
| `ba610ba` | **iOS App (`ios`)** | `v0.0.7.6` | `#100` | **Phase 3.2**: Upgrade `RTPVideoStreamer.swift` to lock 90kHz RTP timestamps to disciplined AbuClock TAI exposure midpoint and embed RFC 5285 (`0xBEDE`) RTP header extension carrying 32-bit BCD timecode + 64-bit TAI ns. |
| `d7021d1` | **UE5 Plugin (`ue`)** | `v0.0.0.1` | `#1` | **Phase 4.1**: Initialize UE5 Plugin version control (`v0.0.0.1`) and merge `AbuClockUE` (`UAbuClockTimecodeProvider`, `UAbuClockCustomTimeStep`, `FAbuClockRuntimeBridge`, `AbuClockFFI.h`) into `LiveLinkAbuTrack`. |
| `4818874` | **UE5 Plugin (`ue`)** | `v0.0.0.2` | `#2` | **Phase 4.2**: Upgrade `FLiveLinkAbuTrackSource` to decode Enriched LiveLink JSON, 29B/37B FreeD (`0xD1`), 41B SMPTE FreeD-TC (`0xD2`), and OpenTrackIO (`OTrk`), stamping `CameraFrameData.MetaData.SceneTime` with `FQualifiedFrameTime` + sub-frame phase. |
| `e6540d7` | **Windows (`win`)** | `v0.1.0.2` | `#95` | **Phase 5.1**: Create `DesktopSync/abu_clock_bridge.py` (Rust FFI / Python Kalman PLL + UDP `50320` Stratum-1 SNTP/Discovery responder + `SCHEDULE_CAPTURE_AT` barrier trigger) and integrate persistent Master SMPTE Timecode Top Bar in `camtrack_desktop_gui.py`. |
| `3ceef6e` | **Windows (`win`)** | `v0.1.0.3` | `#96` | **Phase 5.2**: Upgrade `sync_photos.py` and `camtrack_desktop_gui.py` with Optical Exposure-Midpoint EXIF parsing (`SubSecTimeOriginal` + `ExposureTime`), `Frame-00` Slate Flash Offset auto-solver, Quaternion SLERP interpolation, `.abuscan.json` & COLMAP `images.txt` exporters, and Desktop Clapper Slate window. |
| `0c55d13` | **Windows (`win`)** | `v0.1.0.4` | `#97` | **Phase 5.3**: Upgrade `camtrack_desktop_gui.py` UDP receiver/forwarder with 41B `0xD2` FreeD-TC, OpenTrackIO `timing` block, Timecode-Aligned Telemetry & 4K Video Playout Ring Buffer (`self.pose_history_ring`), and rebuild `dist/abu_track_desktop.exe` (`98.59 MB`). |
| `3f1ebe0` | **Docs & Tests** | Verified | — | **Phase 6**: End-to-end verification test suite and updated project documentation (`README.md`, `abu_track_and_scan_documentation.md`). |
| `a5461a1` | **iOS App (`ios`)** | `v0.0.7.7` | `#101` | **UI/UX Phase 1 Step 1.1**: Create `ContextualHelpView.swift` (`ProTheme` design tokens, `ViewportIconButton`, `WorkflowStepBanner`, `HelpTopic` enum, `InfoHelpButton`, `ContextualHelpSheet` with visual rig coordinate diagram, and 3-tab `QuickStartGuideSheet`). |
| `2b316c4` | **iOS App (`ios`)** | `v0.0.7.8` | `#102` | **UI/UX Phase 1 Step 1.2**: Redesign `ContentView.swift` & `DashboardView.swift` with SF Symbol floating 3D viewport toolbar, Single-Device Viewport Layout Switcher (`Split | Camera | 3D`), Blackmagic-style Horizontal Pro Camera Dial Ribbon, and 3-Card Minimal Telemetry Summary Strip + collapsible Diagnostics drawer. |
| `ee5d356` | **iOS App (`ios`)** | `v0.0.7.9` | `#103` | **UI/UX Phase 1 Step 1.3**: Redesign `SettingsView.swift`, `SessionsView.swift`, and `UEMonitorView.swift` with 3-Way Segmented Category Picker (`🎥 Rig & Optics | 📡 Stream & Clock | ⚙️ Space & System`), `ⓘ` help popovers on every card, and `WorkflowStepBanner` headers. |
| `491dc4b` | **Windows (`win`)** | `v0.1.0.5` | `#98` | **UI/UX Phase 2 Step 2.1**: Add `HoverTooltip`, `CollapsibleCard`, `ScrollableSidebarFrame`, `Segoe UI` typography, `create_workflow_banner`, `show_quick_guide_modal` (with Rig Lever-Arm ASCII diagram), and reordered icon-driven Workspace Tabs in `camtrack_desktop_gui.py`. |
| `e5e1b97` | **Windows (`win`)** | `v0.1.0.6` | `#99` | **UI/UX Phase 2 Step 2.2**: Declutter `Live Track & Stream` and `Scan & Photo Sync` tabs with `ScrollableSidebarFrame`, `CollapsibleCard` drawers, 3D icon toolbar, and `HoverTooltip`s on all controls in `camtrack_desktop_gui.py`. |
| `4cad5a6` | **Windows (`win`)** | `v0.1.0.7` | `#100` | **UI/UX Phase 2 Step 2.3**: Rebuild standalone `dist/abu_track_desktop.exe` (`98.62 MB`) with `v0.1.0.7` minimalist UI/UX redesign. |
| `8ee00c6` | **UE5 Plugin (`ue`)** | `v0.0.0.3` | `#3` | **UI/UX Phase 3 Step 3.1**: Add rich `DisplayName` / `ToolTip` `UPROPERTY` metadata and implement `FLiveLinkAbuTrackSettingsCustomization` (`IDetailCustomization`) with Live SMPTE Timecode HUD card, 1-Click `[Configure UE5 TimecodeProvider & Genlock]` button, and collapsible Quick Guide card. |
| `4559a73` | **Windows (`win`)** | `v0.1.0.8` | `#101` | **UI/UX Phase 4 Verification Fix**: Unify `CollapsibleCard` keyword arguments (`expanded`, `badge_text`, `tooltip_title`/`tooltip_body`, `.body`, `.set_badge`), verify headless `CamTrackDesktopApp` UI instantiation, and rebuild `dist/abu_track_desktop.exe`. |
| `HEAD` | **Windows (`win`)** | `v0.1.0.9` | `#102` | **Frozen EXE Startup Fix**: Fix Python 3.13 `optimize=2` docstring stripping crash (`add_docstring`), keep stdlib `unittest` required by `pyparsing`/`matplotlib`, guard `sys.executable -m pip` against frozen recursive spawning, preserve parent bootloader PID in `kill_zombie_processes()`, and verify frozen EXE with `--self-test`. |

---

## 2. Minimalist UI/UX Redesign, Iconography & Contextual Guides Walkthrough

### 2.1 iOS App Minimalist UI/UX (`ios v0.0.7.7` -> `v0.0.7.9`)
- **Contextual Help & Onboarding System (`Sources/Views/ContextualHelpView.swift`)**:
  - Created `ProTheme` unified studio design tokens, `ViewportIconButton` (30pt height SF Symbol floating pill buttons with tactile haptic/scale feedback), and `WorkflowStepBanner` (`① -> ② -> ③` top strip with `ⓘ` button).
  - Created `HelpTopic` covering all 12 functional areas (`abuClockHud`, `trackingMode`, `viewport3D`, `proCameraRig`, `rigLeverArm`, `udpStreaming`, `rtpVideoStream`, `axisRemapping`, `worldOrigin`, `lidarCapture`, `sessionsExport`, `ueMonitor`), `InfoHelpButton`, `ContextualHelpSheet` (including a visual camera rig coordinate diagram), and the 3-tab `QuickStartGuideSheet` (`📸 Scan & 3DGS`, `📡 UE5 Live Track`, `⏱ Clock & Slate`).
- **Decluttered Dashboard & Blackmagic-Style Camera Ribbon (`Sources/Views/DashboardView.swift` & `Sources/Views/ContentView.swift`)**:
  - Replaced the 7 tiny 8pt text buttons on the 3D Viewport with an SF Symbol `ViewportIconButton` pill bar (`Follow`, `Center`, `Reset`, `Path`, `Frustum`, `AR Comp`, `LiDAR`).
  - Added a **Single-Device Viewport Layout Switcher** (`Split View` | `Camera Full` | `3D Map Full`) so operators can maximize either the live camera feed or the 3D spatial map with a single tap.
  - Replaced the 5 permanently stacked camera sliders with a **Blackmagic-style Horizontal Pro Camera Dial Ribbon** (`FORMAT`, `LENS`, `SHUTTER`, `ISO`, `WB`, `FOCUS` pills that expand only the selected control drawer on tap).
  - Replaced the 12-row telemetry wall of text with a **3-Card Minimal Telemetry Summary Strip** (`POSITION (m)`, `ROTATION (°)`, `RATE & SYNC`) + a collapsible **`Hardware, Network & Clock Diagnostics ▾`** drawer.
- **3-Way Segmented Settings & Guided Sessions/Monitor (`Sources/Views/SettingsView.swift`, `Sources/Views/SessionsView.swift`, `Sources/Views/UEMonitorView.swift`)**:
  - Divided `SettingsView` into 3 clean categories (`🎥 Rig & Optics`, `📡 Stream & Clock`, `⚙️ Space & System`), cutting vertical scroll depth by 70%.
  - Collapsed advanced axis-remapping matrices and 6-axis stage origin overrides into `DisclosureGroup` drawers.

### 2.2 Windows Workstation Minimalist UI/UX (`win v0.1.0.5` -> `v0.1.0.8`)
- **Typography, Hover Tooltips & Scrollable Sidebars (`DesktopSync/camtrack_desktop_gui.py`)**:
  - Switched all UI titles, tabs, buttons, and labels from monospace `Consolas` to clean **`Segoe UI`**, reserving `Consolas` strictly for live timecode, numeric telemetry, and console logs.
  - Built `HoverTooltip` (floating dark-mode card with cyan accent border, bold title, body explanation, and green recommendation), `CollapsibleCard` (clickable `▾/▸` disclosure header with live status badge and `ⓘ` tooltip), and `ScrollableSidebarFrame` (mouse-wheel scrollable left sidebar so all cards fit on 13"–15" 1080p laptop screens without vertical clipping).
  - Reordered and renamed the 6 Notebook tabs to match the natural studio workflow:
    1. `📸 Scan & Photo Sync`
    2. `🕸 3D Spatial Map`
    3. `📡 Live Track & Stream`
    4. `🖥 UE & AR Monitor`
    5. `🎯 Lens Lab`
    6. `📘 Interactive Guide`
  - Added `create_workflow_banner` (`① ... -> ② ... -> ③ ...` + `[ⓘ Quick Help]`) to every tab and a `❓ Quick Guide` modal in the top Master Clock bar featuring a visual Rig Lever-Arm coordinate diagram.
  - Rebuilt standalone `dist/abu_track_desktop.exe` (`98.62 MB < 100 MB`).

### 2.3 Unreal Engine 5 Plugin Slate UI & 1-Click Setup (`ue v0.0.0.3`)
- **Custom Slate Details Panel (`LiveLinkAbuTrackSettingsCustomization.h` / `.cpp`)**:
  - Registered `FLiveLinkAbuTrackSettingsCustomization` (`IDetailCustomization`) for `ULiveLinkAbuTrackSourceSettings` in `LiveLinkAbuTrack.cpp`.
  - Renders a live **Abu Clock ST 2059-2 Master Timecode HUD card** at the top of the UE5 Live Link Source settings with a 16pt monospace SMPTE + BCD readout, active protocol & clock lock badge, and live sub-frame phase progress bar (`SProgressBar`).
  - Added a **1-Click `[Configure UE5 TimecodeProvider & Genlock (1-Click)]`** button (`ULiveLinkAbuTrackSourceSettings::ConfigureEngineTimecodeAndGenlock()`) that automatically instantiates and assigns `UAbuClockTimecodeProvider` and `UAbuClockCustomTimeStep` onto `GEngine` with matching FPS and Drop-Frame settings.
  - Added rich `DisplayName` and `ToolTip` `UPROPERTY` metadata across `LiveLinkAbuTrackSource.h`, `AbuClockTimecodeProvider.h`, and `AbuClockCustomTimeStep.h`.
