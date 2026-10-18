import SwiftUI

struct AcademyView: View {
    var body: some View {
        NavigationView {
            ZStack {
                ProTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Academy Welcome Banner
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "graduationcap.fill")
                                    .font(.title3)
                                    .foregroundColor(ProTheme.accentCyan)
                                Text("ABU TRACK & SCAN ACADEMY")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundColor(ProTheme.textPrimary)
                                Spacer()
                                Text(VersionInfo.version)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(ProTheme.accentCyan)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(ProTheme.surfaceElevated)
                                    .cornerRadius(6)
                            }
                            
                            Text("Complete field guide for 60Hz Visual-Inertial-LiDAR tracking, Abu Clock SMPTE ST 2059-2 genlock, DSLR Lever-Arm calibration, and Unreal Engine 5 / COLMAP / Metashape production pipelines.")
                                .font(.caption2)
                                .foregroundColor(ProTheme.textSecondary)
                                .lineSpacing(3)
                        }
                        .padding(14)
                        .background(ProTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // Lesson Topics List
                        VStack(spacing: 12) {
                            LessonDisclosureGroup(
                                title: "1. Single-Device & Dual-Device Capture Pipelines",
                                icon: "camera.metering.center.weighted",
                                color: ProTheme.accentCyan,
                                content: """
                                • **Active AR Tracking Mode (HI-RES AR + 6DoF EXIF):** While 'START CAPTURE' is active, tapping the shutter button captures a high-resolution ARKit frame paired with an exact Optical Midpoint Stamp (SMPTE ST 12-1 timecode, TAI nanoseconds, 6DoF pose, and LiDAR depth snapshot).
                                
                                • **Standby Optical Pro Mode (48MP HEIC / Apple ProRAW DNG):** When AR tracking is stopped, the hardware camera pipeline unlocks full 48MP HEIC and native Bayer DNG Raw capture with manual ISO and Shutter Speed controls.
                                
                                • **Hot-Shoe Rig Mode (iPhone + DSLR/Mirrorless):** Mount the iPhone onto your DSLR hot-shoe, photograph the **Abu Clock Slate** once for sub-millisecond clock offset calibration, and shoot raw photos on your DSLR while Abu Track logs 60Hz VIO + LiDAR.
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "2. Abu Clock SMPTE ST 2059-2 & Optical Slate",
                                icon: "clock.badge.checkmark.fill",
                                color: .yellow,
                                content: """
                                • **2-State Kalman Filter PLL:** Disciplines the iPhone's Mach continuous clock against the Abu Clock Master (`UDP 50320`) to eliminate crystal frequency drift.
                                
                                • **Full-Screen Digital Clapper Slate:** Tap the top-bar **SLATE** button to open the SMPTE timecode clapper with a Frame-00 White Peak Flash Marker and 10-segment Sub-Frame Phase Sweep Bar (`φ ∈ [0.0, 1.0)`).
                                
                                • **Future-Time Capture Barrier (UDP 50319):** Supports `SCHEDULE_CAPTURE_AT` multi-rig hardware spinlock triggers so every iPhone and PC camera fires within `< 50 µs` of the target TAI nanosecond.
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "3. DSLR Lever-Arm & Single-Source-of-Truth Guard",
                                icon: "ruler.fill",
                                color: .green,
                                content: """
                                • **3D Quaternion Lever-Arm Math:** Rotates your physical offset vector `(dx, dy, dz)` from the iPhone Rear Main (1x) lens to the DSLR focal plane mark (`⌀`) using the live unit quaternion:
                                  `P_camera = P_phone - R(q) · d_lever`
                                
                                • **Double-Compensation Guard:** When Lever-Arm or Stage World Origin offsets are configured on iOS (`Setup → Rig & Optics`), outgoing UDP packets automatically carry `"leverArmApplied": true` and `"originApplied": true`. The Windows Workstation automatically bypasses duplicate offsets and displays an indicator so your pose is never shifted twice.
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "4. Unified Ecosystem Port Topology",
                                icon: "network",
                                color: .orange,
                                content: """
                                • **UDP 8080 (Primary Telemetry):** iOS → Windows Workstation (`Live Link JSON`, `FreeD D1 37B`, `FreeD-TC D2 41B`, or `OpenTrackIO JSON`).
                                • **UDP 8081 (Workstation Forwarder):** Windows Workstation → Unreal Engine 5 (`LiveLinkAbuTrack` plugin). Allows both apps to run on the same PC without port conflicts.
                                • **UDP 5004 (RTP Video Stream):** Hardware H.264/HEVC video with RFC 5285 (`0xBEDE`) 16-byte SMPTE BCD + TAI header extensions.
                                • **UDP 50320 & 50319 (Abu Clock):** `ABU_ECO_V1` auto-discovery + Stratum-1 SNTP (`50320`) and Future-Time Multi-Sensor Capture Barrier (`50319`).
                                • **UDP 53530 (UE5 Discovery):** `ABU_UE5_DISCOVER_V1` zero-config handshake between Windows and Unreal Engine 5.
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "5. Metashape, COLMAP & .abuscan.json Exports",
                                icon: "arrow.up.doc.fill",
                                color: .purple,
                                content: """
                                • **1-Click Session Exports:** Open any take in the **Sessions** tab and tap **SYNC CAMERA IMAGES (SLERP + SLATE)** to generate and share:
                                  1. `metashape_cameras.csv` (14 columns including `smpte_timecode` & `tai_ns`)
                                  2. `<session>.abuscan.json` (`abuscan.manifest.v1` schema with quaternions, intrinsics & LiDAR paths)
                                  3. `images.txt` (Native COLMAP / 3D Gaussian Splatting prior pose manifest)
                                  4. `coverage_cloud.ply` (Voxelized world-space LiDAR surface point cloud)
                                  5. `telemetry_log.csv` (Full 24-column 60Hz trajectory log)
                                """
                            )
                            
                            LessonDisclosureGroup(
                                title: "6. Unreal Engine 5 LiveLink & 1-Click Genlock",
                                icon: "tv.and.mediabox.fill",
                                color: .blue,
                                content: """
                                • **LiveLinkAbuTrack UE5 Plugin:** Receives 6-DOF camera transforms, lens focal length, radial distortion (`K1/K2`), and SMPTE ST 2059-2 timecode directly in Unreal Engine 5.
                                
                                • **1-Click Timecode & Genlock Setup:** In UE5's Live Link panel, click **1-Click Setup Timecode & Genlock** to bind `UAbuClockTimecodeProvider` and `UAbuClockGenlockCustomTimeStep` to `GEngine` with instant toast confirmation and live UDP stream health monitoring.
                                """
                            )
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// Custom disclosure group styling aligned with ProTheme
struct LessonDisclosureGroup: View {
    let title: String
    let icon: String
    let color: Color
    let content: String
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(color)
                    }
                    
                    Text(title)
                        .font(.footnote)
                        .fontWeight(.black)
                        .foregroundColor(ProTheme.textPrimary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ProTheme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(14)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .background(ProTheme.borderSubtle)
                        .padding(.horizontal, 14)
                    
                    Text(.init(content))
                        .font(.caption)
                        .foregroundColor(ProTheme.textSecondary)
                        .lineSpacing(4)
                        .padding(14)
                }
                .background(Color.black.opacity(0.2))
            }
        }
        .background(ProTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isExpanded ? color.opacity(0.45) : ProTheme.borderSubtle, lineWidth: 1)
        )
    }
}
