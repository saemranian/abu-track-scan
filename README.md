# Abu Track & Scan — Enterprise Virtual Production Camera Tracking, LiDAR & Photogrammetry Synchronization Suite

**Repository:** `https://github.com/saemranian/abu-track-scan`

| Component | Latest Version | Build | Core Target |
| :--- | :--- | :--- | :--- |
| **Windows Workstation (`DesktopSync`)** | **`v0.1.0.4`** | `#97` | `DesktopSync/camtrack_desktop_gui.py` & `dist/abu_track_desktop.exe` |
| **iOS App (`Abu Track & Scan`)** | **`v0.0.7.6`** | `#100` | `Sources/` (iPhone 13–17 Pro / Pro Max with LiDAR) |
| **Unreal Engine 5 Plugin (`LiveLinkAbuTrack`)** | **`v0.0.0.2`** | `#2` | `UnrealPlugin/LiveLinkAbuTrack` (`LiveLink` + `AbuClock` Timing Engine) |

---

## Overview

**Abu Track & Scan** is an end-to-end Virtual Production (ICVFX / AR) and 3D Photogrammetry / Gaussian Splatting synchronization ecosystem powered by **Abu Clock** (SMPTE ST 12-1 / ST 2059-2 Timecode Generator & Sub-Microsecond Master Clock):

1. **Abu Scan (Multi-Sensor Photogrammetry & LiDAR Capture):**
   - Synchronizes the iOS RGB Camera (HEIC / ProRAW), iOS LiDAR Depth Scanner (`.ply`), 60Hz VIO + CoreMotion IMU + Barometer + RTK GPS telemetry (`telemetry_log.csv`), and external DSLR/Mirrorless cameras mounted via hot-shoe or multi-camera rigs.
   - **Optical Exposure-Midpoint Timestamping:** Evaluates every photo and LiDAR depth frame at the exact optical exposure midpoint $T_{\text{mid}} = T_{\text{SOF}} + \frac{1}{2}T_{\text{exposure}}$ in 64-bit TAI nanoseconds (`tai_ns`).
   - **Future-Time Barrier Trigger (`SCHEDULE_CAPTURE_AT` / `ABU_TRIG_V1`):** Broadcasts a 56-byte binary barrier command on UDP `50319` (`T_target = now + 50ms`) so multi-rig iOS nodes and workstation triggers fire within $\pm 50\,\mu\text{s}$.
   - **Digital Clapper Slate & Frame-00 Optical Flash Calibration:** High-contrast SMPTE ST 2059-2 digital clapper slate with a Frame-00 (`FF == 00`) pure-white flash marker and sub-frame phase sweep bar ($\phi \in [0, 1)$), paired with an automated Frame-00 luminance detector and Quaternion SLERP interpolator on Windows.
   - **Industry Manifest Exporters:** Exports Agisoft Metashape CSV/XML, RealityScan CSV, Postshot 3DGS JSON, COLMAP `colmap_images.txt`, and `.abuscan.json`.

2. **Abu Track (Real-Time 6DoF Virtual Production & AR Compositing):**
   - Streams 60Hz 6DoF camera tracking, hardware-intrinsic lens distortion ($f_{35\text{mm}}, k_1, k_2$), LiDAR point clouds, and 4K H.264/HEVC RTP video across Ultra-Wide (`13mm`), Main Wide (`24mm`), Telephoto (`77mm`/`120mm`), and Front TrueDepth (`180°` Dual-Camera Simultaneous ARSession) lenses.
   - **Timecode-Stamped Telemetry Protocols:**
     - **Enriched LiveLink JSON** (`taiNs`, `smpteTimecode`, `bcdTimecode`, `subframePhase`, `clockLockState`)
     - **41-Byte SMPTE FreeD-TC (`0xD2`)** (29B FreeD body + 32-bit SMPTE ST 12-1 BCD timecode + 64-bit TAI nanoseconds)
     - **29B / 37B FreeD (`0xD1`)**
     - **OpenTrackIO (`OTrk`)** with `timing` block (`taiNs`, `smpteTimecode`, `bcdTimecode`, `subframePhase`, `frameRate`)
   - **RFC 5285 (`0xBEDE`) RTP Header Extensions:** Embeds the 12-byte Abu Clock header (`bcdTimecode` + `taiNs`) directly into 4K H.264/HEVC RTP video packets (`ID=1, L=11`).
   - **Unified UE5 Plugin (`LiveLinkAbuTrack`):** Combines `FLiveLinkAbuTrackSource` (`FQualifiedFrameTime` sub-frame `SceneTime` stamping), `UAbuClockTimecodeProvider`, and `UAbuClockCustomTimeStep` (`abu_clock_wait_for_next_frame` sub-frame phase-locked engine pacing) in a single Unreal Engine 5 plugin.

---

## Part 1: Abu Clock Synchronization Architecture

```
+-----------------------------------------------------------------------------------+
|                WINDOWS WORKSTATION MASTER (DesktopSync v0.1.0.4)                  |
|  - AbuClockBridge (abuclock.dll FFI / QPC + 2-State Kalman PLL / abu-clock.exe)   |
|  - UDP 50320: ABU_ECO_V1 Auto-Discovery Beacon & Stratum-1 48B SNTP Server        |
|  - UDP 50319: SCHEDULE_CAPTURE_AT (ABU_TRIG_V1 56B) Future-Time Barrier Trigger   |
|  - Timecode-Aligned Telemetry & 4K Video Playout Ring Buffer + UE5 Forwarder      |
+-------------------+-------------------------------------------+-------------------+
                    | UDP 50320 (Discovery/SNTP)                | Local / LAN IPC
                    | UDP 50319 (Barrier Trigger)               v
                    | UDP 8080 / 5000 (Track & RTP Video)  +------------------------+
                    v                                      | UNREAL ENGINE 5.3-5.5  |
+---------------------------------------+                  | LiveLinkAbuTrack v0.0.0.2
| iOS APP (Abu Track & Scan v0.0.7.6)   |----------------->| - FLiveLinkAbuTrackSource
| - AbuClockKit (Kalman PLL + ST 2059)  |  0xD2 / OTrk /   |   (SceneTime stamped)  |
| - Exposure Midpoint (T_sof + T_exp/2) |  LiveLink JSON   | - UAbuClockTimecode    |
| - RFC 5285 (0xBEDE) RTP Video Ext     |                  | - UAbuClockCustomStep  |
+---------------------------------------+                  +------------------------+
```

---

## Part 2: Deploying & Running the Suite

### 1. iOS App (`Sources/`)
1. Open the project in Xcode or **Swift Playgrounds** on an iPhone 13 Pro / 14 Pro / 15 Pro / 16 Pro / 17 Pro (or Pro Max).
2. Ensure all files in `Sources/Managers/` (including `AbuClockKit.swift`, `NTPSyncClient.swift`, `CameraManager.swift`, `MotionAndTrackingManager.swift`, `TelemetryLogger.swift`, `PhotoSyncManager.swift`, `UDPStreamingManager.swift`, `LiveVideoStreamingManager.swift`, `UEMonitoringManager.swift`) and `Sources/Views/` (including `AbuClockSlateView.swift`, `DashboardView.swift`, `ContentView.swift`, `SessionsView.swift`, `SettingsView.swift`, `UEMonitorView.swift`) are included.
3. Grant **Camera**, **Location**, **Motion**, **Photo Library**, and **Local Network** permissions.
4. Upon launch, `AbuClockKit` automatically discovers the Windows Workstation Master on UDP `50320` (`ABU_ECO_V1`), locks its 2-state Kalman PLL via burst SNTP exchanges, and displays live SMPTE ST 2059-2 timecode and lock status (`LOCKED / MASTER / HOLDOVER`) in the top HUD bar.

### 2. Windows Workstation (`DesktopSync/`)
Run the standalone executable `dist/abu_track_desktop.exe` or launch directly via Python:
```powershell
python DesktopSync/camtrack_desktop_gui.py
```
- **Top Master Clock Bar:** Select SMPTE frame rate (`23.976 NDF`, `24 NDF`, `25 NDF`, `29.97 DF`, `29.97 NDF`, `30 NDF`, `50 NDF`, `59.94 DF`, `59.94 NDF`, `60 NDF`), open the **Digital Clapper Slate**, or click **TRIGGER CAPTURE BARRIER (+50ms)** to fire synchronized captures across all discovered iOS nodes.
- **Tab 01 (Sync & Export):** Auto-detect the Frame-00 Optical Flash Slate photo (`AUTO-SOLVE SLATE FLASH OFFSET`), interpolate 6DoF poses at optical exposure midpoints via Quaternion SLERP, and export to Metashape, RealityScan, Postshot, `.abuscan.json`, and COLMAP `colmap_images.txt`.
- **Tab 04 (Live Telemetry Checker):** Receive LiveLink JSON, 41B `0xD2` SMPTE FreeD-TC, 29B/37B `0xD1` FreeD, or OpenTrackIO (`OTrk`), view the timecode-aligned 3D LiDAR + 4K video Cockpit overlay, and forward to Unreal Engine.

### 3. Unreal Engine 5 Plugin (`UnrealPlugin/LiveLinkAbuTrack/`)
1. Copy `UnrealPlugin/LiveLinkAbuTrack` into your UE5 project's `Plugins/` folder.
2. Enable **Abu Track LiveLink & AbuClock Timing Plugin** in `Edit -> Plugins`.
3. In **Project Settings -> Timecode**, set **Timecode Provider** to `AbuClockTimecodeProvider` and **Custom TimeStep** to `AbuClockCustomTimeStep` for hardware-disciplined frame pacing.
4. In **Window -> Virtual Production -> Live Link**, add an **Abu Track LiveLink** source (UDP port `8080`). Incoming camera poses automatically populate `MetaData.SceneTime` (`FQualifiedFrameTime` with sub-frame phase) for Composure and Timecode Synchronizer.

---

## Part 3: Automated Versioning & Audit Trail

Every component edit is tracked via `build_version_tracker.py` using the 4-part decimal rollover scheme (`vA.B.C.D`, where `.9` rolls over to `.1.0`, e.g., `v0.1.0.9` $\rightarrow$ `v0.1.1.0`):

```powershell
python -B build_version_tracker.py --target <win|ios|ue|all> --task "Description of change"
```

See [VERSION_CHANGELOG.md](VERSION_CHANGELOG.md) and [app_versions.json](app_versions.json) for the complete chronological audit trail.
