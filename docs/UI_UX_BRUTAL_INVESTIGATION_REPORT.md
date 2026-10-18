# Brutal UI & UX Forensic Investigation Report — Abu Track & Scan Ecosystem

**Audited Versions:**
- **Windows Desktop Workstation:** `v0.1.0.9` (Build `#102`) — `DesktopSync/camtrack_desktop_gui.py`
- **iOS Companion App:** `v0.0.7.9` (Build `#103`) — `Sources/Views/`
- **Unreal Engine 5 Plugin:** `v0.0.0.3` (Build `#3`) — `UnrealPlugin/LiveLinkAbuTrack/`
- **Host Display Benchmark:** `2560 × 1440` QHD (`ProcessDpiAwareness = 2`, `Tk DPI = 96.0`)

---

## Executive Summary & Severity Matrix

An automated live widget-tree geometry/font inspection combined with a full source-code UX audit across all 3 platforms uncovered **48 distinct UI and UX issues** spanning microscopic typography (`8pt` fonts), horizontal widget crushing (`197px` button crushed to `36px`), unscaled High-DPI window geometry, main-thread UI freezes during photo synchronization, split-brain 3D viewports, dead-code iOS camera pipelines (`RAW/48MP` silently ignored during ARKit tracking), gesture conflicts, and dangerous cross-device double-compensation traps.

| ID | Category | Platform | Issue Summary | Severity |
| :--- | :--- | :--- | :--- | :--- |
| **WIN-UI-01** | Window & DPI | Windows | Hardcoded `1180x800` window on `2560x1440` QHD screen (46% width), uncentered, no DPI scaling, and `minsize=(114, 1)` allows total UI collapse | **CRITICAL** |
| **WIN-UI-02** | Typography | Windows | **588 widgets use `8pt` font** and **312 widgets use `9pt` font** (`~10.6px`), rendering logs, badges, and help text unreadable on 1440p/4K monitors | **CRITICAL** |
| **WIN-UI-03** | Layout Clipping | Windows | Top Master Clock bar packs 11 horizontal widgets into `1180px`, crushing **`⚡ Trigger Multi-Rig (+50ms)`** from `req_w=197px` down to **`actual_w=36px`** on every tab | **CRITICAL** |
| **WIN-UI-04** | Layout Clipping | Windows | Tab 2 (`📡 Live Track & Stream`) left sidebar gets `388px` (`weight=4`) while inner widgets require `461px` (`-73px` deficit), truncating every `CollapsibleCard` header and IP/Timecode readout | **CRITICAL** |
| **WIN-UI-05** | Hit Targets | Windows | Interactive buttons (`ⓘ Quick Help` at `91×21px`, `📐 View Rig Diagram` at `125×19px`, card `ⓘ` at `18×17px`) fall well below the `28px–32px` desktop minimum | **HIGH** |
| **WIN-UI-06** | Vertical Overflow | Windows | Even with progressive disclosure, Tab 0 (`741px > 651px`) and Tab 2 (`939px > 651px` collapsed, `1350px` expanded) overflow vertically at launch | **HIGH** |
| **WIN-UX-01** | Responsiveness | Windows | `run_synchronization()` runs **synchronously on the Tkinter MainThread**, freezing the entire application ("Not Responding") during CSV parsing & DSLR EXIF tagging | **CRITICAL** |
| **WIN-UX-02** | Input Hijacking | Windows | `ScrollableSidebarFrame` uses `canvas.bind_all("<MouseWheel>")` on `<Enter>`, hijacking scroll events globally from `Combobox` dropdowns, `Text` logs, and 3D viewports | **HIGH** |
| **WIN-UX-03** | Split-Brain 3D | Windows | Tab 1 uses sluggish **Matplotlib `Axes3D`** (no toolbar, no camera follow/reset), while Tab 2 uses a **2D Tkinter Canvas software 3D renderer** with completely different mouse controls | **HIGH** |
| **WIN-UX-04** | Modal Spam | Windows | Clicking or arrow-keying through `photo_listbox` in Tab 1 immediately fires a blocking `grab_set()` modal window (`400×530`) on every single selection event | **CRITICAL** |
| **WIN-UX-05** | Missing Feature | Windows | The **1-Click Windows Firewall Rule (`UDP 8080`)** button was dropped from the UI, even though both the iOS Guide and Windows Manual instruct users to click `'FIX WINDOWS FIREWALL (8080)'` | **HIGH** |
| **WIN-UX-06** | Stale Copy | Windows | Tab 5 (`📘 Interactive Guide`) `write_documentation_manual()` contains legacy cyberpunk copy and wrong tab numbers (`"tab 04 // LIVE TELEMETRY CHECKER"`, `"02 // DYNAMIC UDP FORWARDER"`) | **MEDIUM** |
| **IOS-UI-01** | Typography | iOS | Widespread **`8pt`, `8.5pt`, and `9.5pt` fonts** in `ContentView`, `DashboardView`, and `AbuClockSlateView` violate Apple HIG (`11pt` minimum) and are illegible on a camera rig | **CRITICAL** |
| **IOS-UX-01** | Dead Pipeline | iOS | In Single-Device mode, starting AR tracking switches from `AVCaptureSession` to `ARSession.captureHighResolutionFrame`, which **silently ignores `RAW (DNG)` and `48MP`** while leaving `cameraManager.capturePhoto()` unreachable dead code | **CRITICAL** |
| **IOS-UX-02** | Gesture Conflict | iOS | `DashboardView` wraps `PointCloudVisualizerView` (`MultiTouchGestureOverlay`) inside a vertical `ScrollView`, causing 1-finger 3D orbit drags to fight with page scrolling | **HIGH** |
| **IOS-UX-03** | Duplicate Guides | iOS | Two competing help systems: top-bar `?` (`QuickStartGuideSheet`) vs bottom tab `Guide` (`AcademyView.swift`), the latter containing outdated `v0.0.5` copy | **MEDIUM** |
| **IOS-UX-04** | Incomplete Export | iOS | `SessionDetailView` uses legacy un-themed colors and only offers 3 share buttons (`Metashape CSV`, `PLY`, `Raw Logs`), omitting `.abuscan.json` and `colmap_images.txt` | **HIGH** |
| **UE-UX-01** | Silent Action | UE5 | Clicking `Configure UE5 TimecodeProvider & Genlock (1-Click)` only writes to `UE_LOG` with **zero visual toast (`FSlateNotificationManager`)** or UI confirmation | **MEDIUM** |
| **UE-UX-02** | Stale Telemetry | UE5 | LiveLink Details panel displays the last received `LiveSmpteTimecode` forever when UDP packets stop, with no `ONLINE / OFFLINE` heartbeat indicator or packet age | **HIGH** |
| **ARCH-UX-01** | Double Offset | Cross-App | `Lever-Arm (dx,dy,dz)`, `Stage Origin`, `Axis Remap`, and `-90° Pitch Offset` exist in **both** iOS and Windows/UE5 with no handshake, risking silent **double-compensation** | **CRITICAL** |
| **ARCH-UX-02** | Port Confusion | Cross-App | Unclear port topology across `UDP 8080` (iOS $\rightarrow$ PC Telemetry), `UDP 8081` (PC $\rightarrow$ UE5 Forwarder), `UDP 8082` vs `UDP 5004` (RTP Video), and `UDP 5000` (Discovery) | **HIGH** |

---

## Concrete Step-by-Step Remediation Blueprint

### Phase 1 (P0): Windows Desktop Geometry, DPI, Font Hierarchy & Zero-Clipping Layout
1. **Adaptive High-DPI Window Sizing & Minimum Size (`WIN-UI-01`):**
   - Detect screen resolution on launch; default to `min(1540, int(screen_w * 0.85)) × min(940, int(screen_h * 0.85))` centered on screen, and enforce `self.root.minsize(1280, 800)`.
2. **Eliminate the `8pt` Font Plague (`WIN-UI-02`):**
   - Raise the global font floor in `camtrack_desktop_gui.py`:
     - `8pt` $\rightarrow$ `9.5pt` / `10pt` (`Muted.TLabel`, console logs, badges, axis hints).
     - `9pt` $\rightarrow$ `10pt` (`TLabel`, `TButton`, `TCheckbutton`, `TRadiobutton`).
     - Raise interactive button hit targets (`ⓘ Quick Help`, `📐 View Rig Diagram`, card `ⓘ`) to `>= 28px` height (`WIN-UI-05`).
3. **Fix Top Master Clock Bar Crushing (`WIN-UI-03`):**
   - Move low-level engineering strings (`BCD: 0x00000000` and 19-digit `TAI` nanoseconds) into a hover tooltip / Clapper Slate modal, freeing `380px` in the top bar so `⚡ Trigger Multi-Rig (+50ms)` (`req_w=197px`) renders at 100% width with room to spare.
4. **Fix Left Sidebar Horizontal & Vertical Clipping Across All Tabs (`WIN-UI-04`, `WIN-UI-06`):**
   - Enforce a consistent `minsize=460` on column 0 (`ScrollableSidebarFrame`) across all tabs, wrap multi-IP strings (`wraplength=240`), and remove the redundant `52px` title banner inside Tab 0's sidebar.

### Phase 2 (P0): Windows Desktop UX, Threading, 3D Viewport & Firewall Fixes
1. **Background Thread for `run_synchronization()` (`WIN-UX-01`):**
   - Offload `run_synchronization()` to a daemon worker thread with thread-safe `self.root.after(0, ...)` progress bar and log updates so the GUI never freezes during photo sync.
2. **Fix Mouse-Wheel Hijacking (`WIN-UX-02`):**
   - Update `ScrollableSidebarFrame._on_mousewheel` to inspect `event.widget`: if the cursor is over a `Text`, `Listbox`, or `Combobox`, let the child widget scroll naturally instead of scrolling the sidebar canvas.
3. **Eliminate Modal Popup Spam in Tab 1 & Upgrade 3D Viewport Controls (`WIN-UX-03`, `WIN-UX-04`):**
   - Change `photo_listbox` single-click (`<<ListboxSelect>>`) to **highlight the selected camera frustum in the 3D plot and show an inline summary bar**, and bind `<Double-Button-1>` (or an `🔍 Inspect Photo` button) to open the detail window (non-blocking).
   - Add a unified 3D camera toolbar above Tab 1's 3D plot (`🔄 Reset View`, `📐 Top View`, `📐 Side View`, `🎥 Iso View`, `➕/➖ Point Size`).
4. **Restore 1-Click Firewall Button & Update Tab 5 Manual (`WIN-UX-05`, `WIN-UX-06`):**
   - Add the `🛡 Fix Windows Firewall (UDP 8080/5004)` button directly inside Tab 2 Card 01 (`Network Receiver`) and rewrite `write_documentation_manual()` in Tab 5 to match the exact current 6-tab architecture.

### Phase 3 (P0): iOS App Typography, Honest Camera Pipeline, Fixed Bottom Bar & Exports
1. **Raise All `8pt–9pt` Fonts to Apple HIG Minimum (`>= 10.5pt–11pt`) (`IOS-UI-01`):**
   - Upgrade all microscopic labels across `ContentView.swift`, `DashboardView.swift`, and `AbuClockSlateView.swift`.
2. **Fix Single-Device Camera Pipeline & Honest Format Controls (`IOS-UX-01`):**
   - Enable the shutter button both before and during tracking:
     - When AR tracking is active, clearly label capture mode as **`HI-RES AR FRAME (JPG / HEIC + 6DoF EXIF)`** and auto-select `JPG` or `HEIC` so `RAW (DNG)` / `48MP` are never falsely advertised while ARKit owns the sensor; when AR tracking is stopped, allow full `AVCaptureSession` `48MP` / `RAW (DNG)` standalone capture.
3. **Eliminate Scroll-vs-3D Orbit Conflict & Pin Primary Controls (`IOS-UX-02`):**
   - Pin the primary `START/STOP TRACKING` + `SHUTTER` control bar to the bottom safe area (`safeAreaInset(edge: .bottom)`) and isolate gesture recognition on `PointCloudVisualizerView` so 1-finger 3D orbit never scrolls the page.
4. **Unify iOS Guide & Upgrade `SessionDetailView` (`IOS-UX-03`, `IOS-UX-04`):**
   - Update `AcademyView.swift` to modern `ProTheme` cards matching the current v0.0.7.9 workflows and ports (`5004` video, `8080` telemetry).
   - Upgrade `SessionDetailView` to `ProTheme` and add 1-click `ShareLink` buttons for `.abuscan.json` and `colmap_images.txt`.
   - Bind `SettingsView` GPS toggle to `@AppStorage("isGpsEnabled")` shared with `DashboardView`.

### Phase 4 (P1): UE5 Toast Notifications, Stream Heartbeat & Cross-Platform Double-Offset Guard
1. **UE5 LiveLink Visual Toast & Stream Health Indicator (`UE-UX-01`, `UE-UX-02`):**
   - Add `FSlateNotificationManager` toast confirmation when clicking `Configure UE5 TimecodeProvider & Genlock (1-Click)` and display live stream age/heartbeat status in the Details panel.
2. **Cross-Device Double-Compensation Guard (`ARCH-UX-01`):**
   - Include `"lever_arm_applied"` and `"origin_applied"` flags in the iOS JSON telemetry packet so Windows Desktop automatically warns/prevents double-applying Lever-Arm or Stage Origin offsets.
