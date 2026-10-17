# Walkthrough: Multi-Component Version Control & Abu Clock Sub-Microsecond Integration

This repository walkthrough documents:
1. **The Multi-Component 4-Part Decimal Rollover Version Control System** (`win`, `ios`, `ue`) managed by [`build_version_tracker.py`](../build_version_tracker.py), [`app_versions.json`](../app_versions.json), and [`VERSION_CHANGELOG.md`](../VERSION_CHANGELOG.md).
2. **The Complete Phase 0–6 Integration of Abu Clock (`v0.0.0.14`)** across the **iOS App (`Abu Track & Scan`)**, **Windows Workstation (`DesktopSync`)**, and **Unreal Engine 5 Plugin (`LiveLinkAbuTrack`)**.

---

## 1. How the Multi-Component Version Control System Works

Every edit to any of the three components in **Abu Track & Scan** is tracked independently using a **base-10 4-part decimal rollover scheme** (`vA.B.C.D`, where `.9` rolls over to `.1.0`, e.g. `v0.1.0.9` $\rightarrow$ `v0.1.1.0`):

### 1.1 Automated CLI Command
Before each commit, run [`build_version_tracker.py`](../build_version_tracker.py):
```bash
# Bump Windows Workstation version
python build_version_tracker.py --component win --task "Description of Windows feature or fix"

# Bump iOS App version
python build_version_tracker.py --component ios --task "Description of iOS feature or fix"

# Bump UE5 Plugin version
python build_version_tracker.py --component ue --task "Description of UE5 Plugin feature or fix"
```

### 1.2 Files Synchronized on Every Bump
- **[`app_versions.json`](../app_versions.json)**: Canonical JSON state storing each component's current `version`, `build_number`, `updated_at`, `last_task`, and full chronological `history[]`.
- **[`VERSION_CHANGELOG.md`](../VERSION_CHANGELOG.md)**: Human-readable Markdown audit log table of every version bump across all three platforms.
- **[`DesktopSync/app_version.py`](../DesktopSync/app_version.py)**: Python constants (`APP_VERSION`, `BUILD_NUMBER`, `BUILD_TIMESTAMP`, `LAST_TASK`, `IOS_VERSION`, `UE_PLUGIN_VERSION`) displayed in the Windows GUI title bar and header.
- **[`Sources/AppVersion.swift`](../Sources/AppVersion.swift)** & **[`project.yml`](../project.yml)**: Swift `AppVersion` struct and XcodeGen `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` displayed in the iOS Dashboard and Settings.
- **[`UnrealPlugin/LiveLinkAbuTrack/LiveLinkAbuTrack.uplugin`](../UnrealPlugin/LiveLinkAbuTrack/LiveLinkAbuTrack.uplugin)** & **[`LiveLinkAbuTrackVersion.h`](../UnrealPlugin/LiveLinkAbuTrack/Source/LiveLinkAbuTrack/Public/LiveLinkAbuTrackVersion.h)**: UE5 plugin manifest version and C++ macros (`ABU_TRACK_UE_PLUGIN_VERSION`).

---

## 2. Phase-by-Phase Walkthrough of Abu Clock Integration (Phases 0–6)

| Phase | Component & Version | Commit | Key Deliverables |
| :--- | :--- | :--- | :--- |
| **Phase 0** | Baseline Setup (`win v1.0.1`, `ios v0.0.7`, `ue v0.0.0.1`) | `7dc78e0` | Created `build_version_tracker.py`, `app_versions.json`, `VERSION_CHANGELOG.md`, and `LiveLinkAbuTrackVersion.h`. |
| **Phase 1.1** | `ios v0.0.7.1` (Build #95) | `dd680dc` | Created `Sources/Managers/AbuClockKit.swift`: 2-state Kalman PLL on `mach_continuous_time()`, UDP `50320` Stratum-1 SNTP + `ABU_ECO_V1` auto-discovery, automatic `FIELD_MASTER` promotion, and UDP `50319` `SCHEDULE_CAPTURE_AT` listener. |
| **Phase 1.2** | `ios v0.0.7.2` (Build #96) | `da3b58f` | Created `Sources/Views/AbuClockSlateView.swift` (full-screen Digital Clapper Slate with `Frame-00` optical flash + 1kHz beep) and added live SMPTE Timecode HUD bar to `DashboardView.swift`. |
| **Phase 2.1–2.2** | `ios v0.0.7.3` (Build #97) | `5b2dcbb` | Upgraded `CameraManager.swift` with optical exposure-midpoint TAI/SMPTE timestamping ($t_{\text{mid}} = t_{\text{sof}} + T_{\text{exp}}/2$), deterministic timecode filenames, and future-time barrier shutter firing. |
| **Phase 2.3–2.4** | `ios v0.0.7.4` (Build #98) | `6d07105` | Upgraded `MotionManager.swift` (60Hz CSV + LiDAR `.ply`/`.pts` TAI/SMPTE headers) and `PhotoSyncManager.swift` (sub-ms SLERP pose interpolation, `Frame-00` Slate Flash Offset solver, `.abuscan.json` & COLMAP `images.txt` export). |
| **Phase 3.1** | `ios v0.0.7.5` (Build #99) | `fc3303d` | Upgraded `UDPStreamingManager.swift` with Enriched LiveLink JSON, 41-byte `0xD2` `SMPTE FreeD-TC` binary telemetry, and OpenTrackIO `PTP_SMPTE_ST2059_2` timing block. |
| **Phase 3.2** | `ios v0.0.7.6` (Build #100) | `ba610ba` | Upgraded `RTPVideoStreamer.swift` to lock 90kHz RTP timestamps to disciplined AbuClock TAI exposure midpoints and embed RFC 5285 (`0xBEDE`) RTP header extensions carrying 32-bit BCD timecode + 64-bit TAI ns. |
| **Phase 4.1** | `ue v0.0.0.1` (Build #1) | `d7021d1` | Merged `AbuClockUE` (`UAbuClockTimecodeProvider`, `UAbuClockCustomTimeStep`, `FAbuClockRuntimeBridge`, `AbuClockFFI.h`) into `LiveLinkAbuTrack`. |
| **Phase 4.2** | `ue v0.0.0.2` (Build #2) | `4818874` | Upgraded `FLiveLinkAbuTrackSource` to decode Enriched LiveLink JSON, 29B/37B FreeD (`0xD1`), 41B SMPTE FreeD-TC (`0xD2`), and OpenTrackIO (`OTrk`), stamping `CameraFrameData.MetaData.SceneTime` with `FQualifiedFrameTime` + sub-frame phase. |
| **Phase 5.1** | `win v0.1.0.2` (Build #95) | `e6540d7` | Created `DesktopSync/abu_clock_bridge.py` (Rust FFI / Python Kalman PLL + UDP `50320` Stratum-1 SNTP/Discovery server + `SCHEDULE_CAPTURE_AT` barrier trigger) and added persistent Master SMPTE Timecode Top Bar to `camtrack_desktop_gui.py`. |
| **Phase 5.2** | `win v0.1.0.3` (Build #96) | `3ceef6e` | Upgraded `DesktopSync/sync_photos.py` and `camtrack_desktop_gui.py` with EXIF Exposure-Midpoint calculation, `Frame-00` Slate Flash Offset auto-solver, Quaternion SLERP interpolation, `.abuscan.json` & COLMAP exporters, and Desktop Clapper Slate window. |
| **Phase 5.3** | `win v0.1.0.4` (Build #97) | `0c55d13` | Upgraded `camtrack_desktop_gui.py` UDP receiver/forwarder with 41B `0xD2` FreeD-TC, OpenTrackIO `timing` block, Timecode-Aligned Telemetry & 4K Video Playout Ring Buffer (`self.pose_history_ring`), and rebuilt `dist/abu_track_desktop.exe` (`98.59 MB`). |
| **Phase 6** | Verification & Docs | `3f1ebe0` | Verified all 5 automated test suites and updated `README.md` and `abu_track_and_scan_documentation.md`. |
