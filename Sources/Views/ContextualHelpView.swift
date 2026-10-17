import SwiftUI

// MARK: - Unified Studio Minimalist Theme Tokens

struct ProTheme {
    static let background = Color(red: 0.02, green: 0.03, blue: 0.08)
    static let cardBackground = Color(red: 0.055, green: 0.075, blue: 0.145)
    static let surfaceElevated = Color(red: 0.08, green: 0.11, blue: 0.20)
    static let borderSubtle = Color.white.opacity(0.10)
    static let accentCyan = Color(red: 0.0, green: 0.88, blue: 0.96)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.65)
    static let statusNominal = Color(red: 0.18, green: 0.88, blue: 0.48)
    static let statusWarning = Color(red: 1.0, green: 0.76, blue: 0.15)
    static let statusCritical = Color(red: 1.0, green: 0.28, blue: 0.34)
}

// MARK: - Minimalist SF Symbol Viewport Pill Button (34x34pt touch target)

struct ViewportIconButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    var activeColor: Color = ProTheme.accentCyan
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .foregroundColor(isActive ? activeColor : Color.white.opacity(0.68))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isActive ? activeColor.opacity(0.18) : Color.black.opacity(0.68))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? activeColor.opacity(0.75) : Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Workflow Step Banner

struct WorkflowStepBanner: View {
    let stepsText: String
    let helpTopic: HelpTopic

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ProTheme.accentCyan)
            Text(stepsText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(ProTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            InfoHelpButton(topic: helpTopic)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ProTheme.cardBackground.opacity(0.9))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ProTheme.borderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Contextual Help Topics

enum HelpTopic: String, Identifiable {
    case abuClockHud
    case viewport3D
    case proCameraHud
    case loggingParams
    case dslrRigOffsets
    case originOverrides
    case cameraOptics
    case lidarDepth
    case udpLiveStream
    case coordinateSpace
    case sessionsSync
    case ueMonitor

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .abuClockHud: return "clock.badge.checkmark.fill"
        case .viewport3D: return "cube.transparent.fill"
        case .proCameraHud: return "camera.aperture"
        case .loggingParams: return "waveform.path.ecg"
        case .dslrRigOffsets: return "ruler.fill"
        case .originOverrides: return "scope"
        case .cameraOptics: return "camera.metering.center.weighted"
        case .lidarDepth: return "viewfinder.rectangular"
        case .udpLiveStream: return "antenna.radiowaves.left.and.right"
        case .coordinateSpace: return "move.3d"
        case .sessionsSync: return "photo.stack.fill"
        case .ueMonitor: return "tv.and.mediabox"
        }
    }

    var title: String {
        switch self {
        case .abuClockHud: return "Abu Clock & SMPTE Timecode"
        case .viewport3D: return "3D Spatial Viewport & AR HUD"
        case .proCameraHud: return "Pro Camera & Exposure-Midpoint Sync"
        case .loggingParams: return "Capture Mode & Logging Rate"
        case .dslrRigOffsets: return "DSLR / Cinema Rig 6-DOF Calibration"
        case .originOverrides: return "World Origin (0,0,0) Overrides"
        case .cameraOptics: return "Lens Selection, Offsets & Distortion"
        case .lidarDepth: return "LiDAR Depth & Point Cloud Capture"
        case .udpLiveStream: return "LiveLink, FreeD-TC & 4K RTP Streaming"
        case .coordinateSpace: return "Coordinate System & Axis Presets"
        case .sessionsSync: return "Session Export, SLERP & Slate Sync"
        case .ueMonitor: return "UE5 Return Feed & AR Monitor"
        }
    }

    var subtitle: String {
        switch self {
        case .abuClockHud: return "Sub-microsecond TAI + SMPTE ST 2059-2 synchronization"
        case .viewport3D: return "Interactive 6-DOF trajectory, frustum, and LiDAR preview"
        case .proCameraHud: return "Manual exposure controls & multi-rig barrier shutter"
        case .loggingParams: return "Choose between External DSLR Rig or Single-Device capture"
        case .dslrRigOffsets: return "Physical lever-arm & boresight from iPhone to main camera"
        case .originOverrides: return "Anchor your tracking session to a physical stage marker"
        case .cameraOptics: return "Per-lens nodal offsets and radial distortion (K1/K2)"
        case .lidarDepth: return "Timecode-stamped .PLY / .PTS 3D depth snapshots"
        case .udpLiveStream: return "Real-time camera tracking and genlocked video for UE5"
        case .coordinateSpace: return "1-click coordinate presets for UE5, Postshot, and ARKit"
        case .sessionsSync: return "Match photos to sub-ms poses and export .abuscan.json / COLMAP"
        case .ueMonitor: return "Low-latency wireless director's monitor from PC / Unreal"
        }
    }

    var summary: String {
        switch self {
        case .abuClockHud:
            return "Abu Clock disciplines the iPhone's hardware oscillator (mach_continuous_time) to a Windows Workstation Master over UDP 50320 using a 2-state Kalman Filter PLL. If no PC is on the network, the iPhone automatically becomes a FIELD_MASTER so peer iPhones and cameras can still lock to it."
        case .viewport3D:
            return "Displays the real-time 6-DOF camera trajectory, 3D orientation frustum, and live LiDAR point cloud. Use the floating SF Symbol icon bar at the bottom-right to toggle Follow mode, recenter the camera, reset the world origin, or switch into AR Composite mode."
        case .proCameraHud:
            return "Every photo and video frame is stamped at its exact optical exposure midpoint (t_mid = t_sof + ExposureTime / 2) in TAI nanoseconds and SMPTE timecode. Tap any parameter pill (Shutter, ISO, WB, Focus, Zoom) in the dial bar to adjust that control without cluttering the viewfinder."
        case .loggingParams:
            return "Select 60 Hz for maximum temporal accuracy during rapid camera motion or 30 Hz for long battery-saving scans. Choose 'DSLR Rig (Dual)' when the iPhone is mounted as a tracker on an external cinema/mirrorless camera, or 'Single-Device' when shooting photos directly on the iPhone."
        case .dslrRigOffsets:
            return "When the iPhone is mounted on top of or beside a DSLR/cinema camera, ARKit tracks the iPhone's rear Wide (1x) lens. Entering the physical X/Y/Z distance (in cm) and Pitch/Yaw/Roll angle (in deg) from the iPhone lens to the DSLR sensor nodal point mathematically transforms every pose to the exact DSLR lens center."
        case .originOverrides:
            return "By default, ARKit starts at (0, 0, 0) where you tap Start. If your stage has a measured survey marker (e.g., 150 cm height), enable Origin Overrides so the session starts at that exact world coordinate."
        case .cameraOptics:
            return "ARKit always tracks the world using the Rear Main (1x) camera + LiDAR. When you switch the video stream to Ultra-Wide (0.5x), Telephoto (3x/5x), or Front TrueDepth, Abu Track automatically applies the factory sensor-to-sensor translation and 180° front-camera rotation so the AR overlay and point cloud stay locked."
        case .lidarDepth:
            return "Captures 3D Time-of-Flight depth maps alongside your poses and photos, saved as standard .PLY or .PTS point clouds with embedded @abu_clock_tai_ns and @abu_clock_smpte_tc headers for Jawset Postshot and RealityCapture."
        case .udpLiveStream:
            return "Streams 60 Hz camera poses and lens intrinsics over UDP to the Windows Workstation or directly into Unreal Engine 5. Supports Enriched LiveLink JSON, 29B/37B FreeD (0xD1), 41B SMPTE FreeD-TC (0xD2), and OpenTrackIO (OTrk), plus 4K RTP video with RFC 5285 timecode headers."
        case .coordinateSpace:
            return "Different 3D tools use different coordinate conventions. Simply pick a preset ('ARKit', 'Unreal Engine', 'Metashape', or 'Blender') and all 12 axis/rotation/LiDAR remappings are configured automatically."
        case .sessionsSync:
            return "Each recorded session contains 60 Hz CSV telemetry, LiDAR point clouds, and photos. Use Photo Sync to interpolate exact sub-millisecond poses via Quaternion SLERP and export ready-to-train .abuscan.json and COLMAP manifests."
        case .ueMonitor:
            return "Receives a live MJPEG return feed from the Windows Workstation / Unreal Engine 5 on UDP port 5005 so the camera operator can frame virtual sets directly on the iPhone."
        }
    }

    var recommendation: String {
        switch self {
        case .abuClockHud: return "Recommended: Use 29.97 DF or 24 fps to match your cinema camera or UE5 project frame rate."
        case .viewport3D: return "Tip: Tap the Reset (↺) icon while holding the rig steady on your stage mark to zero the world origin."
        case .proCameraHud: return "Tip: Use a fast shutter speed (1/250s or faster) during handheld photogrammetry to eliminate motion blur."
        case .loggingParams: return "Recommended: 60 Hz for both Virtual Production tracking and handheld DSLR scanning."
        case .dslrRigOffsets: return "Measure from the center of the iPhone Rear Main (1x) lens to the DSLR sensor plane mark (⌀)."
        case .originOverrides: return "Leave disabled (0, 0, 0) unless aligning multiple sessions to a fixed stage coordinate system."
        case .cameraOptics: return "Rear Wide (1x) provides the widest native ARKit + LiDAR overlap."
        case .lidarDepth: return "Recommended: 'Medium' or 'High' confidence in PLY format for clean Gaussian Splatting initialization."
        case .udpLiveStream: return "Recommended: 'LiveLink JSON' or 'SMPTE FreeD-TC (41B)' on Port 8080 for Unreal Engine 5."
        case .coordinateSpace: return "Use 'Unreal Engine' for Virtual Production or 'ARKit' / 'Metashape' for 3DGS & Photogrammetry."
        case .sessionsSync: return "Photograph the Clapper Slate (🎬) at the start of a DSLR take to auto-calibrate your camera's clock offset."
        case .ueMonitor: return "Ensure your iPhone and PC Workstation are on the same 5GHz Wi-Fi or Ethernet-to-Lightning/USB-C LAN."
        }
    }

    var steps: [String] {
        switch self {
        case .abuClockHud:
            return [
                "Launch the Windows Workstation app on the same LAN — the iPhone auto-discovers it on UDP 50320.",
                "Verify the lock badge turns green (LOCKED_MASTER) or cyan (FIELD_MASTER if standalone).",
                "Tap the 'SLATE' button to open the full-screen Frame-00 optical flash clapper for external cameras."
            ]
        case .dslrRigOffsets:
            return [
                "Look at the back of your iPhone (screen facing you) while mounted on your camera rig.",
                "X Offset (+Right / -Left): Measure horizontal distance (cm) from iPhone 1x lens to DSLR lens axis.",
                "Y Offset (+Up / -Down): Measure vertical distance (cm) from iPhone 1x lens to DSLR sensor center.",
                "Z Offset (-Forward / +Back): Measure depth distance (cm) along the shooting direction."
            ]
        case .udpLiveStream:
            return [
                "Enter your PC Workstation or UE5 machine's IP address (or auto-discovered Master IP) and Port 8080.",
                "Choose 'LiveLink JSON', 'SMPTE FreeD-TC (41B)', or 'OpenTrackIO'.",
                "Toggle 'ENABLE LIVE STREAMING' (and 'STREAM 4K VIDEO TO PC' if using the PC AR compositor)."
            ]
        default:
            return []
        }
    }
}

// MARK: - Reusable 'ⓘ' Info Button

struct InfoHelpButton: View {
    let topic: HelpTopic
    @State private var showSheet = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSheet = true
        }) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ProTheme.accentCyan.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(ProTheme.accentCyan.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            ContextualHelpSheet(topic: topic)
        }
    }
}

// MARK: - Contextual Help Modal Sheet

struct ContextualHelpSheet: View {
    let topic: HelpTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                ProTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Header Card
                        HStack(spacing: 14) {
                            Image(systemName: topic.icon)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(ProTheme.accentCyan)
                                .frame(width: 52, height: 52)
                                .background(ProTheme.accentCyan.opacity(0.12))
                                .cornerRadius(12)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(topic.title)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(ProTheme.textPrimary)
                                Text(topic.subtitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ProTheme.textSecondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ProTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))

                        // How It Works
                        VStack(alignment: .leading, spacing: 8) {
                            Label("HOW IT WORKS", systemImage: "sparkles")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ProTheme.accentCyan)

                            Text(topic.summary)
                                .font(.system(size: 13))
                                .foregroundColor(ProTheme.textPrimary)
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ProTheme.cardBackground)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))

                        // Special Visual Diagram for DSLR Rig Offsets / Coordinate Space
                        if topic == .dslrRigOffsets || topic == .coordinateSpace {
                            rigCoordinateDiagramCard
                        }

                        // Step-by-Step Instructions (if any)
                        if !topic.steps.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("STEP-BY-STEP", systemImage: "list.number")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(ProTheme.statusNominal)

                                ForEach(Array(topic.steps.enumerated()), id: \.offset) { idx, step in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(idx + 1)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(ProTheme.background)
                                            .frame(width: 20, height: 20)
                                            .background(ProTheme.accentCyan)
                                            .clipShape(Circle())

                                        Text(step)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(ProTheme.textPrimary)
                                    }
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ProTheme.cardBackground)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
                        }

                        // Pro Recommendation Box
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(ProTheme.statusNominal)
                                .font(.system(size: 18))
                            Text(topic.recommendation)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ProTheme.textPrimary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ProTheme.statusNominal.opacity(0.1))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ProTheme.statusNominal.opacity(0.35), lineWidth: 1))
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ProTheme.accentCyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var rigCoordinateDiagramCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("CAMERA RIG AXIS REFERENCE (ARKIT NATIVE)", systemImage: "view.3d")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(ProTheme.statusWarning)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("+X Axis : Right side of iPhone screen")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(ProTheme.textPrimary)
                }
                HStack(spacing: 8) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("+Y Axis : Top edge of iPhone (Up)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(ProTheme.textPrimary)
                }
                HStack(spacing: 8) {
                    Circle().fill(ProTheme.accentCyan).frame(width: 8, height: 8)
                    Text("-Z Axis : Shooting direction (Out of rear lens)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(ProTheme.textPrimary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProTheme.background)
            .cornerRadius(8)
        }
        .padding(16)
        .background(ProTheme.cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
    }
}

// MARK: - Full Interactive Quick-Start Guide Sheet (3 Workflows)

struct QuickStartGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0

    var body: some View {
        NavigationView {
            ZStack {
                ProTheme.background.ignoresSafeArea()

                VStack(spacing: 12) {
                    // Segmented Workflow Picker
                    Picker("Workflow", selection: $selectedTab) {
                        Text("📸 Scan & 3DGS").tag(0)
                        Text("📡 UE5 Live Track").tag(1)
                        Text("⏱ Clock & Slate").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            if selectedTab == 0 {
                                guideSection(
                                    icon: "camera.viewfinder",
                                    title: "Workflow 1: Photogrammetry & 3D Gaussian Splatting",
                                    subtitle: "Sync DSLR or iPhone photos with 60Hz VIO poses & LiDAR depth",
                                    steps: [
                                        ("1. Choose Mode", "In Setup -> Capture & Rig, pick 'DSLR Rig (Dual)' if mounted on an external camera, or 'Single-Device' to shoot with the iPhone camera."),
                                        ("2. Flash the Clapper Slate", "If using an external DSLR/mirrorless camera, tap 'SLATE' on the top bar and take 1 photo of the Frame-00 white flash to lock the DSLR clock offset to < 0.5 frame."),
                                        ("3. Start Recording", "On the Monitor tab, tap 'START LOGGING' (and press the shutter button or PC Barrier Trigger to capture photos + LiDAR snapshots)."),
                                        ("4. Export to Postshot / COLMAP", "Open the Data tab, select your session, and export '.abuscan.json' + COLMAP 'images.txt' or transfer to the Windows Workstation.")
                                    ]
                                )
                            } else if selectedTab == 1 {
                                guideSection(
                                    icon: "antenna.radiowaves.left.and.right",
                                    title: "Workflow 2: Real-Time Virtual Production (UE5)",
                                    subtitle: "Stream genlocked 60Hz camera tracking & 4K video to Unreal Engine 5",
                                    steps: [
                                        ("1. Auto-Discover or Set Target IP", "In Setup -> Track & Clock, verify the Target IP matches your PC Workstation or UE5 workstation (Port 8080)."),
                                        ("2. Select Wire Protocol", "Choose 'LiveLink JSON', 'SMPTE FreeD-TC (41B)', or 'OpenTrackIO'. All 3 carry exact SMPTE ST 2059-2 timecode and sub-frame phase."),
                                        ("3. Enable Streaming", "Toggle 'ENABLE LIVE STREAMING' (and optional 'STREAM 4K VIDEO TO PC' on Port 5004)."),
                                        ("4. Connect in Unreal Engine 5", "In UE5 Window -> Virtual Production -> Live Link, add 'Abu Track LiveLink Source' on Port 8080 and click 'Configure UE5 TimecodeProvider & Genlock'.")
                                    ]
                                )
                            } else {
                                guideSection(
                                    icon: "clock.badge.checkmark.fill",
                                    title: "Workflow 3: Abu Clock Multi-Rig Synchronization",
                                    subtitle: "Sub-microsecond TAI PLL, Future-Time Barrier Trigger & Digital Slate",
                                    steps: [
                                        ("1. Zero-Config LAN Lock", "When the Windows Workstation runs on the same LAN, the iPhone automatically locks via UDP 50320 Stratum-1 SNTP (green 'LOCKED_MASTER' badge)."),
                                        ("2. Standalone Field Master", "Away from a PC, the iPhone promotes itself to 'FIELD_MASTER' so other iPhones on the same Wi-Fi/hotspot lock to it automatically."),
                                        ("3. Multi-Rig Barrier Capture", "Click 'Trigger Multi-Rig Capture' on the PC (or UDP 50319) to fire all connected iPhones at the exact same future TAI nanosecond."),
                                        ("4. Optical Exposure Midpoint", "Every photo and 4K RTP video frame is timestamped at t_mid = t_sof + (ExposureTime / 2), eliminating motion-blur phase lag.")
                                    ]
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Abu Track & Scan Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ProTheme.accentCyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func guideSection(icon: String, title: String, subtitle: String, steps: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(ProTheme.accentCyan)
                    .frame(width: 48, height: 48)
                    .background(ProTheme.accentCyan.opacity(0.12))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(ProTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ProTheme.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProTheme.cardBackground)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))

            ForEach(Array(steps.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.0)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ProTheme.accentCyan)
                    Text(item.1)
                        .font(.system(size: 12))
                        .foregroundColor(ProTheme.textPrimary)
                        .lineSpacing(3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ProTheme.cardBackground)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ProTheme.borderSubtle, lineWidth: 1))
            }
        }
    }
}
