# Abu Track & Scan — Component Version Control & Audit Log

This file is automatically maintained by [`build_version_tracker.py`](file:///c:/Users/USer/.gemini/antigravity/scratch/ios_app_cam_track_01/build_version_tracker.py).
Every code edit to the **Windows Workstation (`win`)**, **iOS App (`ios`)**, or **Unreal Engine 5 Plugin (`ue`)** increments that component's 4-part decimal version (`vA.B.C.D`, rolling `.9` $\rightarrow$ `.1.0`) and records the implemented task.

| Timestamp | Component | Version | Build | Implemented Task |
| :--- | :--- | :--- | :---: | :--- |
| `2026-06-03 22:39:23` | **Windows Workstation (DesktopSync)** | `v1.0.1` | `#94` | Baseline Build #94 (`e1795b0`) prior to 4-part `v0.1.0.2` transition |
| `2026-06-03 22:39:23` | **iOS App (Abu Track & Scan)** | `v0.0.7` | `#94` | Baseline Build #94 (`e1795b0`) prior to 4-part `v0.0.7.1` transition |
| `2026-06-03 22:39:23` | **UE5 Plugin (LiveLinkAbuTrack)** | `v1.0.0` (untracked) | `#0` | Baseline static `.uplugin` prior to 4-part `v0.0.0.1` transition |
| `2026-10-18 01:18:22` | **iOS App (Abu Track & Scan)** | `v0.0.7.1` | `#95` | Embed AbuClockKit 2-state Kalman PLL on mach_continuous_time, UDP 50320 Stratum-1 SNTP + ABU_ECO_V1 auto-discovery, and UDP 50319 SCHEDULE_CAPTURE_AT barrier listener |
| `2026-10-18 01:20:21` | **iOS App (Abu Track & Scan)** | `v0.0.7.2` | `#96` | Add live SMPTE timecode HUD bar, telemetry rows, and full-screen Abu Clock Digital Clapper Slate with Frame-00 optical flash marker |
