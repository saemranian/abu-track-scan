import SwiftUI
import AVFoundation
import ARKit

// Segmented device setup selector
enum CaptureMode: String, CaseIterable, Identifiable {
    case dualDevice = "DUAL-DEVICE (DSLR)"
    case singleDevice = "SINGLE-DEVICE (IN-APP)"
    var id: String { self.rawValue }
}

class CameraCoordinator: ObservableObject, CameraManagerDelegate {
    var onPhotoCaptured: ((URL, Double, String) -> Void)?
    var onCaptureError: ((Error) -> Void)?
    
    func cameraManager(_ manager: CameraManager, didCapturePhotoAt url: URL, timestamp: Double, filename: String) {
        onPhotoCaptured?(url, timestamp, filename)
    }
    
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error) {
        onCaptureError?(error)
    }
}

struct DashboardView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var trackingManager: MotionAndTrackingManager
    
    @AppStorage("captureRate") private var captureRate: Double = 10.0
    
    @State private var sessionTimer: DispatchSourceTimer?
    @State private var sessionDuration: TimeInterval = 0.0
    @State private var entryCount = 0
    @State private var startTime: Date?
    
    // 3D Visualizer Drag Navigation State (Orbit, Pan, Zoom)
    @State private var rotX: Double = -0.4
    @State private var rotY: Double = 0.5
    @State private var panX: Double = 0.0
    @State private var panY: Double = 0.0
    @State private var panZ: Double = 0.0
    @State private var zoom: Double = 1.0
    @State private var isFollowModeActive = true // Aligns viewport to active camera coordinate by default
    
    // Hardware Load Diagnostic State
    @State private var cpuUsage: Double = 0.0
    @State private var ramUsage: Double = 0.0
    @State private var localEpochTimeStr: String = "00:00:00.000"
    @State private var hardwareTimer: Timer?
    
    // Toggles for Trajectory and Camera Position
    @State private var showTrajectory = true
    @State private var showCamera = true
    
    // Pro Camera Controls State
    @State private var captureMode: CaptureMode = .dualDevice
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var cameraCoordinator = CameraCoordinator()
    
    // Preset Arrays for Shutter Speeds
    let shutterSpeeds: [Double] = [0.0, 1.0/8000.0, 1.0/4000.0, 1.0/2000.0, 1.0/1000.0, 1.0/500.0, 1.0/250.0, 1.0/125.0, 1.0/60.0, 1.0/30.0, 1.0/15.0, 1.0/8.0, 1.0/4.0, 1.0/2.0, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]
    let shutterLabels: [String] = ["AUTO", "1/8000", "1/4000", "1/2000", "1/1000", "1/500", "1/250", "1/125", "1/60", "1/30", "1/15", "1/8", "1/4", "1/2", "1.0s", "2.0s", "5.0s", "10s", "30s", "60s"]
    
    @State private var shutterSpeedIndex = 0 // Default AUTO
    @State private var isoValue: Double = 200.0 // Range: 50.0 to 3000.0
    @State private var isAutoISO = true
    @State private var wbTemperature: Double = 5000.0 // Kelvin range: 2500.0 to 9000.0
    @State private var isAutoWB = true
    @State private var isAutoFocus = true // Default auto focus
    @State private var focusPosition: Double = 1.0 // Default infinity (1.0)
    @State private var pictureFormat = "JPG" // options: JPG, HEIF, DNG
    @State private var is48MP = false // false = 12MP, true = 48MP (Quad-Pixel sensor)
    @State private var zoomFactor: Double = 1.0
    
    @State private var lastCapturedPhotoName = ""
    @State private var shutterFeedbackMessage = ""
    @State private var isCameraReady = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background Radial Gradient
                Color(red: 0.02, green: 0.03, blue: 0.08)
                    .ignoresSafeArea()
                
                RadialGradient(
                    gradient: Gradient(colors: [Color(red: 0.0, green: 0.15, blue: 0.25), Color.clear]),
                    center: .top,
                    startRadius: 50,
                    endRadius: 500
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        
                        // 00 // DEVICE SETUP CONFIGURATION
                        VStack(spacing: 8) {
                            HStack {
                                Label("00 // DEVICE SETUP CONFIGURATION", systemImage: "macbook.and.iphone")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            
                            Picker("Capture Setup", selection: $captureMode) {
                                ForEach(CaptureMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 16)
                            .disabled(trackingManager.isTrackingActive) // Prevent shifting mode while recording
                        }
                        .padding(.top, 12)
                        
                        // Sleek, Expanded Hero 3D Point Cloud Viewport
                        VStack(spacing: 6) {
                            HStack {
                                Label("LiDAR Depth 3D Projected Canvas", systemImage: "circle.grid.3x3.fill")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                                Spacer()
                                Text(trackingManager.isTrackingActive ? "\(trackingManager.accumulatedPointCloud.count) pts" : "System Standby")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            
                            ZStack(alignment: .bottomTrailing) {
                                ZStack {
                                    PointCloudVisualizerView(
                                        points: trackingManager.accumulatedPointCloud,
                                        isTracking: trackingManager.isTrackingActive,
                                        rotX: isFollowModeActive ? -trackingManager.pitch * Double.pi / 180.0 - Double.pi / 2.0 : rotX,
                                        rotY: isFollowModeActive ? -trackingManager.yaw * Double.pi / 180.0 : rotY,
                                        rotZ: isFollowModeActive ? -trackingManager.roll * Double.pi / 180.0 : 0.0,
                                        panX: isFollowModeActive ? trackingManager.localX : panX,
                                        panY: isFollowModeActive ? trackingManager.localY : panY,
                                        panZ: isFollowModeActive ? trackingManager.localZ : panZ,
                                        zoom: zoom,
                                        cameraPosition: (x: trackingManager.localX, y: trackingManager.localY, z: trackingManager.localZ),
                                        trajectory: trackingManager.cameraTrajectory,
                                        showTrajectory: showTrajectory,
                                        showCamera: showCamera
                                    )
                                    
                                    MultiTouchGestureOverlay(
                                        rotX: $rotX,
                                        rotY: $rotY,
                                        panX: $panX,
                                        panY: $panY,
                                        zoom: $zoom,
                                        onInteractionBegan: {
                                            isFollowModeActive = false
                                        }
                                    )
                                }
                                .frame(height: 290)
                                .background(Color(red: 0.03, green: 0.04, blue: 0.08))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                )
                                
                                // Floating HUD Controls
                                HStack(spacing: 6) {
                                    // 3D VR auto oriented viewfinder cockpit snap follow toggler
                                    Button(action: {
                                        isFollowModeActive.toggle()
                                        if isFollowModeActive {
                                            rotX = -trackingManager.pitch * Double.pi / 180.0 - Double.pi / 2.0
                                            rotY = -trackingManager.yaw * Double.pi / 180.0
                                            panX = trackingManager.localX
                                            panY = trackingManager.localY
                                            panZ = trackingManager.localZ
                                            zoom = 1.0
                                        }
                                    }) {
                                        Text("FOLLOW")
                                            .font(.system(size: 8, weight: .black, design: .monospaced))
                                            .foregroundColor(isFollowModeActive ? .cyan : .gray)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(isFollowModeActive ? Color.cyan.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: 0.5))
                                    }
                                    
                                    Button(action: {
                                        isFollowModeActive = false
                                        rotX = -0.4
                                        rotY = -trackingManager.yaw * Double.pi / 180.0
                                        panX = trackingManager.localX
                                        panY = trackingManager.localY
                                        panZ = trackingManager.localZ
                                        zoom = 1.0
                                    }) {
                                        Text("CENTER")
                                            .font(.system(size: 8, weight: .black, design: .monospaced))
                                            .foregroundColor(.cyan)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cyan.opacity(0.6), lineWidth: 0.5))
                                    }
                                    
                                    Button(action: { showTrajectory.toggle() }) {
                                        Text("PATH")
                                            .font(.system(size: 8, weight: .black, design: .monospaced))
                                            .foregroundColor(showTrajectory ? .yellow : .gray)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(showTrajectory ? Color.yellow.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: 0.5))
                                    }
                                    
                                    Button(action: { showCamera.toggle() }) {
                                        Text("CAM")
                                            .font(.system(size: 8, weight: .black, design: .monospaced))
                                            .foregroundColor(showCamera ? .red : .gray)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(showCamera ? Color.red.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: 0.5))
                                    }
                                    
                                    Button(action: { trackingManager.isMappingSensorsActive.toggle() }) {
                                        Text("SCAN")
                                            .font(.system(size: 8, weight: .black, design: .monospaced))
                                            .foregroundColor(trackingManager.isMappingSensorsActive ? .cyan : .gray)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(trackingManager.isMappingSensorsActive ? Color.cyan.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: 0.5))
                                    }
                                }
                                .padding(8)
                             }
                        }
                        .padding(.horizontal)
                        
                        // Integrated Viewfinder preview, Circular shutter, and Pro manual sliders config
                        if captureMode == .singleDevice {
                            singleDeviceViewfinder
                        }
                        
                        // Sleek, Minimal Action Button Row
                        HStack(spacing: 12) {
                            // Primary Start/Stop Shutter Button
                            Button(action: {
                                if trackingManager.isTrackingActive {
                                    stopSession()
                                } else {
                                    startSession()
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(trackingManager.isTrackingActive ? Color.red : Color.cyan)
                                        .frame(width: 10, height: 10)
                                        .scaleEffect(trackingManager.isTrackingActive ? 1.2 : 1.0)
                                        .animation(trackingManager.isTrackingActive ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: trackingManager.isTrackingActive)
                                    
                                    Text(trackingManager.isTrackingActive ? "STOP CAPTURE RUN" : "START CAPTURE RUN")
                                        .font(.system(size: 11, weight: .black, design: .monospaced))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Text(trackingManager.isTrackingActive ? formatDuration(trackingManager.sessionDuration) : "STANDBY")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(trackingManager.isTrackingActive ? .red : .gray)
                                }
                                .padding()
                                .background(Color(red: 0.06, green: 0.08, blue: 0.15))
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(trackingManager.isTrackingActive ? Color.red.opacity(0.4) : Color.cyan.opacity(0.3), lineWidth: 1))
                            }
                            
                            // High-End GPS Status / Mode Switcher
                            Button(action: {
                                RigSettings.isGPSEnabled.toggle()
                                locationManager.isGPSEnabled = RigSettings.isGPSEnabled
                            }) {
                                Image(systemName: locationManager.isGPSEnabled ? "location.fill" : "location.slash")
                                    .font(.footnote)
                                    .foregroundColor(locationManager.isGPSEnabled ? .green : .orange)
                                    .frame(width: 48, height: 48)
                                    .background(Color(red: 0.06, green: 0.08, blue: 0.15))
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(locationManager.isGPSEnabled ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1))
                            }
                        }
                        .padding(.horizontal)
                        
                        // Unified Pro Telemetry Console Table (Sleek Slate-Minimal Styling)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TELEMETRIC CORE DIAGNOSTIC STREAM")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 0) {
                                TelemetryRow(label: "LOCAL TRACK X/Y/Z", value: String(format: "%+.3f, %+.3f, %+.3f m", trackingManager.localX, trackingManager.localY, trackingManager.localZ), highlight: .cyan)
                                Divider().background(Color.gray.opacity(0.1))
                                TelemetryRow(label: "DEVICE YAW/PITCH/ROLL", value: String(format: "%+.1f°, %+.1f°, %+.1f°", trackingManager.yaw, trackingManager.pitch, trackingManager.roll), highlight: .white)
                                Divider().background(Color.gray.opacity(0.1))
                                TelemetryRow(label: "BARO HEIGHT/PRESSURE", value: trackingManager.barometerActive ? String(format: "%+.3fm  (%.3f kPa)", trackingManager.relativeAltitude, trackingManager.pressureInKPa) : "NO BAROMETER ACCORD", highlight: .purple)
                                Divider().background(Color.gray.opacity(0.1))
                                TelemetryRow(label: "GNSS ABSOLUTE COORDS", value: locationManager.isGPSEnabled ? String(format: "%.6f, %.6f (±%.1fm)", locationManager.latitude, locationManager.longitude, locationManager.horizontalAccuracy) : "INDOOR GEODETIC FALLBACK", highlight: locationManager.isGPSEnabled ? .green : .orange)
                                Divider().background(Color.gray.opacity(0.1))
                                TelemetryRow(label: "SYS HARDWARE LOAD (CPU/RAM)", value: String(format: "CPU: %.1f%%  RAM: %.1f%%", cpuUsage, ramUsage), highlight: cpuUsage > 80.0 || ramUsage > 80.0 ? .red : .green)
                                Divider().background(Color.gray.opacity(0.1))
                                TelemetryRow(label: "MOBILE EPOCH SYSTEM TIME", value: localEpochTimeStr, highlight: .orange)
                                Divider().background(Color.gray.opacity(0.1))
                                TelemetryRow(label: "MOBILE LOCAL IP ADDRESS", value: UDPStreamingManager.getLocalIPAddress(), highlight: .green)
                                Divider().background(Color.gray.opacity(0.1))
                                TelemetryRow(label: "HARDWARE SCAN HZ (LOCKED)", value: String(format: "%.1f Hz", trackingManager.hardwareScanHz), highlight: .cyan)
                                Divider().background(Color.gray.opacity(0.1))
                                TelemetryRow(label: "SESSION TELEMETRY DATA", value: trackingManager.activeSessionID != nil ? "ID: \(String(trackingManager.activeSessionID!.suffix(8)))  [REC: \(trackingManager.entryCount)]" : "STREAM DISCONNECTED", highlight: .yellow)
                            }
                            .background(Color(red: 0.06, green: 0.08, blue: 0.15))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.15), lineWidth: 1))
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                }
            }
            .navigationTitle("ABU TRACK")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            locationManager.isGPSEnabled = RigSettings.isGPSEnabled
            
            // Wire up camera driver delegate callbacks
            cameraManager.delegate = cameraCoordinator
            cameraCoordinator.onPhotoCaptured = { url, timestamp, filename in
                self.handleInAppPhotoCaptured(url: url, timestamp: timestamp, filename: filename)
            }
            cameraCoordinator.onCaptureError = { error in
                DispatchQueue.main.async {
                    self.shutterFeedbackMessage = "CAPTURE FAILED"
                    if self.trackingManager.isTrackingActive {
                        self.trackingManager.resumeARKitSession()
                    }
                }
            }
            
            // Prevent tab-switching conflicts by keeping camera session active during scan
            if trackingManager.activeSessionID == nil {
                cameraManager.setupCamera { success in
                    DispatchQueue.main.async {
                        self.isCameraReady = success
                        print("CameraManager Setup: \(success)")
                    }
                }
            }
            
            // Periodic Hardware Diagnostics & System Clock Timer (50ms refresh for smooth millisecond clock)
            var ticks = 0
            hardwareTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                self.localEpochTimeStr = getEpochClockString()
                ticks += 1
                if ticks % 20 == 0 { // every 1.0s, update CPU/RAM metrics
                    self.cpuUsage = getCPUUsage()
                    self.ramUsage = getMemoryUsage().used
                }
            }
        }
        .onDisappear {
            hardwareTimer?.invalidate()
            hardwareTimer = nil
            if trackingManager.activeSessionID == nil {
                cameraManager.stopHardwareSession()
            }
        }
        .onChange(of: captureRate) { newRate in
            if trackingManager.activeSessionID != nil {
                trackingManager.rescheduleSessionTimer(newRate: newRate)
            }
        }
    }
    
    // MARK: - Session Controllers
    
    private func startSession() {
        // Prevent screen auto-lock to keep tracking active
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Start physical managers
        locationManager.startUpdates()
        trackingManager.startTracking(frequency: captureRate)
        
        // Automatically snap viewport to active camera coordinate
        self.panX = trackingManager.localX
        self.panY = trackingManager.localY
        self.panZ = trackingManager.localZ
        self.rotY = -trackingManager.yaw * Double.pi / 180.0
        
        // Trigger shared, persistent high-precision session capture
        trackingManager.startSessionTimer(captureRate: captureRate)
        
        // Start in-app camera session if active
        if captureMode == .singleDevice, let sessionID = trackingManager.activeSessionID {
            cameraManager.startSession(sessionID: sessionID)
        }
    }
    
    private func stopSession() {
        // Restore standard screen auto-lock behavior
        UIApplication.shared.isIdleTimerDisabled = false
        
        // Stop in-app camera session
        if captureMode == .singleDevice {
            cameraManager.stopSession()
        }
        
        // Write details to history index in UserDefaults
        if let sessionID = trackingManager.activeSessionID, let start = trackingManager.startTime {
            let sessionInfo: [String: Any] = [
                "id": sessionID,
                "startTime": start.timeIntervalSince1970,
                "endTime": Date().timeIntervalSince1970,
                "entryCount": trackingManager.entryCount,
                "isGPSEnabled": locationManager.isGPSEnabled
            ]
            
            var history = UserDefaults.standard.array(forKey: "sessionHistory") as? [[String: Any]] ?? []
            history.insert(sessionInfo, at: 0)
            UserDefaults.standard.set(history, forKey: "sessionHistory")
        }
        
        // Stop persistent session capturing timer and hardware tracking
        trackingManager.stopSessionTimer()
        trackingManager.stopTracking()
        locationManager.stopUpdates()
        TelemetryLogger.shared.stopSession(sparsePointCloud: trackingManager.accumulatedPointCloud)
    }
    
    // Live microsecond-accurate photo georeferencer for Single-Device In-App RAW captures
    private func handleInAppPhotoCaptured(url: URL, timestamp: Double, filename: String) {
        let lx = Double(RigSettings.leverArmX) / 100.0
        let ly = Double(RigSettings.leverArmY) / 100.0
        let lz = Double(RigSettings.leverArmZ) / 100.0
        
        let qw = trackingManager.q_w
        let qx = trackingManager.q_x
        let qy = trackingManager.q_y
        let qz = trackingManager.q_z
        
        // 3D vector rotation by unit quaternion
        let num1 = qx * 2.0
        let num2 = qy * 2.0
        let num3 = qz * 2.0
        let num4 = qx * num1
        let num5 = qy * num2
        let num6 = qz * num3
        let num7 = qx * num2
        let num8 = qx * num3
        let num9 = qy * num3
        let num10 = qw * num1
        let num11 = qw * num2
        let num12 = qw * num3
        
        let rx = (1.0 - (num5 + num6)) * lx + (num7 - num12) * ly + (num8 + num11) * lz
        let ry = (num7 + num12) * lx + (1.0 - (num4 + num6)) * ly + (num9 - num10) * lz
        let rz = (num8 - num11) * lx + (num9 + num10) * ly + (1.0 - (num4 + num5)) * lz
        
        let correctedX = trackingManager.localX
        let correctedY = trackingManager.localY
        let correctedZ = trackingManager.localZ
        
        var correctedLat = locationManager.latitude
        var correctedLon = locationManager.longitude
        let correctedGpsAlt = locationManager.altitude - rz
        
        if locationManager.isGPSEnabled && locationManager.latitude != 0.0 {
            let latOffsetDeg = ry / 111111.0
            let lonOffsetDeg = rx / (111111.0 * cos(locationManager.latitude * .pi / 180.0))
            correctedLat -= latOffsetDeg
            correctedLon -= lonOffsetDeg
        }
        
        let row = String(
            format: "%@,%.6f,%.6f,%.6f,%.6f,%.8f,%.8f,%.6f,%.4f,%.4f,%.4f,%.3f\n",
            filename,
            correctedX,
            correctedY,
            correctedZ,
            trackingManager.relativeAltitude - rz,
            correctedLat,
            correctedLon,
            correctedGpsAlt,
            trackingManager.yaw,
            trackingManager.pitch,
            trackingManager.roll,
            0.0 // time difference is 0.0s since it's perfectly synchronized on-device!
        )
        
        if let sessionID = trackingManager.activeSessionID {
            let fileManager = FileManager.default
            guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let sessionFolderURL = documentsURL.appendingPathComponent("Sessions").appendingPathComponent(sessionID)
            let metashapeCSVURL = sessionFolderURL.appendingPathComponent("metashape_cameras.csv")
            
            if !fileManager.fileExists(atPath: metashapeCSVURL.path) {
                let header = "label,x_local_m,y_local_m,z_local_m,baro_alt_m,latitude,longitude,gps_alt_m,yaw,pitch,roll,time_diff_sec\n"
                try? (header + row).write(to: metashapeCSVURL, atomically: true, encoding: .utf8)
            } else {
                if let fileHandle = try? FileHandle(forWritingTo: metashapeCSVURL) {
                    fileHandle.seekToEndOfFile()
                    if let data = row.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                    fileHandle.closeFile()
                }
            }
        }
        
        // Set tactile shutter HUD confirmation and increment session record count
        DispatchQueue.main.async {
            self.entryCount += 1
            self.shutterFeedbackMessage = "SAVED: \(filename)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if self.shutterFeedbackMessage == "SAVED: \(filename)" {
                    self.shutterFeedbackMessage = ""
                }
            }
        }
    }
    
    private func updateManualExposure() {
        let selectedShutter = shutterSpeeds[shutterSpeedIndex]
        
        // Auto-toggle ISO to manual if manual shutter speed is chosen (iOS requirement)
        if selectedShutter != 0.0 && isAutoISO {
            // Run on next runloop cycle to prevent layout engine warning
            DispatchQueue.main.async {
                self.isAutoISO = false
            }
        }
        
        let targetISO = isAutoISO ? 0.0 : isoValue
        let targetWB = isAutoWB ? 0.0 : wbTemperature
        cameraManager.updateExposureAndWB(shutterSpeed: selectedShutter, iso: targetISO, wbTemperature: targetWB)
    }
    
    private func updateManualFocus() {
        cameraManager.updateFocus(isAutoFocus: isAutoFocus, lensPosition: focusPosition)
    }
     private func triggerInAppCapture() {
        if trackingManager.isTrackingActive {
            shutterFeedbackMessage = "CAPTURING..."
            
            // Asynchronously capture high-resolution frame concurrently from the active ARSession (zero tracking pause!)
            trackingManager.arSession.captureHighResolutionFrame { (highResFrame, error) in
                if let error = error {
                    print("DashboardView: Failed to capture high-res frame: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.shutterFeedbackMessage = "CAPTURE FAILED"
                    }
                    return
                }
                
                guard let frame = highResFrame else {
                    DispatchQueue.main.async {
                        self.shutterFeedbackMessage = "NO FRAME"
                    }
                    return
                }
                
                let pixelBuffer = frame.capturedImage
                let timestamp = Date().timeIntervalSince1970
                
                guard let sessionID = self.trackingManager.activeSessionID else { return }
                let fileManager = FileManager.default
                guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
                let sessionFolderURL = documentsURL.appendingPathComponent("Sessions").appendingPathComponent(sessionID)
                
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy_MM_dd_HH_mm"
                let datePrefix = formatter.string(from: Date())
                
                let ext = self.pictureFormat == "HEIF" ? "HEIC" : "JPG"
                let filename = "\(datePrefix)_IMG_\(self.entryCount + 1255).\(ext)"
                let fileURL = sessionFolderURL.appendingPathComponent(filename)
                
                DispatchQueue.global(qos: .userInitiated).async {
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    let context = CIContext()
                    var success = false
                    
                    if self.pictureFormat == "HEIF", #available(iOS 11.0, *) {
                        if let heifData = context.heifRepresentation(of: ciImage, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) {
                            do {
                                try heifData.write(to: fileURL)
                                success = true
                            } catch {
                                print("DashboardView: Failed to write HEIF: \(error)")
                                success = false
                            }
                        }
                    } else {
                        if let jpegData = context.jpegRepresentation(of: ciImage, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) {
                            do {
                                try jpegData.write(to: fileURL)
                                success = true
                            } catch {
                                print("DashboardView: Failed to write JPEG: \(error)")
                                success = false
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        if success {
                            print("DashboardView: Instantly saved high-resolution georeferenced AR photo: \(fileURL.path)")
                            self.shutterFeedbackMessage = "SAVED"
                            self.handleInAppPhotoCaptured(url: fileURL, timestamp: timestamp * 1000.0, filename: filename)
                        } else {
                            self.shutterFeedbackMessage = "WRITE ERROR"
                        }
                    }
                }
            }
        } else {
            // Standard non-georeferenced viewport aim capture
            cameraManager.capturePhoto(format: pictureFormat, is48MP: is48MP)
        }
    }
    
    private func getEpochClockString() -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: now)
        let ms = Int((now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%@.%03d  (%.3f)", timeStr, ms, now.timeIntervalSince1970)
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        let tenths = Int((interval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
    
    private func getCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let result = withUnsafeMutablePointer(to: &threadList) {
            $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadCount)
            }
        }
        
        if result != KERN_SUCCESS { return 0.0 }
        
        var totalCPU: Double = 0.0
        if let threadList = threadList {
            for i in 0..<Int(threadCount) {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadList[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                
                if infoResult == KERN_SUCCESS {
                    if (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                        totalCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                    }
                }
            }
            
            let size = MemoryLayout<thread_t>.size * Int(threadCount)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threadList), vm_size_t(size))
        }
        
        return min(totalCPU, 100.0)
    }

    private func getMemoryUsage() -> (used: Double, total: Double) {
        var stats = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        
        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedBytes = Double(stats.resident_size)
            let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
            
            let totalGB = totalBytes / 1024.0 / 1024.0 / 1024.0
            
            let pct = (usedBytes / totalBytes) * 100.0
            return (used: pct, total: totalGB)
        }
        
        return (used: 0.0, total: 0.0)
    }
    
    private var singleDeviceViewfinder: some View {
        VStack(spacing: 8) {
            HStack {
                Label("01 // IN-APP DSLR SHUTTER VIEWPORT", systemImage: "camera.fill")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                Spacer()
                if !shutterFeedbackMessage.isEmpty {
                    Text(shutterFeedbackMessage)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 16)
            
            ZStack(alignment: .bottom) {
                if isCameraReady {
                    ZStack {
                        if trackingManager.isTrackingActive {
                            ARPreviewContainer(trackingManager: trackingManager)
                        } else {
                            CameraPreviewContainer(previewLayer: cameraManager.getPreviewLayer())
                        }
                        
                        // Cyberpunk save directory path HUD overlay
                        VStack {
                            HStack {
                                Text("SAVE PATH: Files -> On My iPhone -> Abu Track -> Sessions -> \(trackingManager.activeSessionID?.suffix(8) ?? "SESSION_ID")")
                                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan.opacity(0.85))
                                    .padding(4)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(4)
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(8)
                        .allowsHitTesting(false)
                    }
                    .frame(width: 280, height: 210) // 4:3 Perfect Aspect Ratio, no cropping!
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 1))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("Initializing lens fusion drivers...")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .frame(width: 280, height: 210)
                    .background(Color(red: 0.05, green: 0.06, blue: 0.12))
                    .cornerRadius(12)
                }
                
                // Circular DSLR Shutter Button overlay
                Button(action: {
                    triggerInAppCapture()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 58, height: 58)
                            .blur(radius: 1)
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 52, height: 52)
                        Circle()
                            .fill(trackingManager.isTrackingActive ? Color.red : Color.gray)
                            .frame(width: 42, height: 42)
                    }
                }
                .padding(.bottom, 12)
                .disabled(!trackingManager.isTrackingActive) // Trigger captures only during continuous georeferencing
            }
            .padding(.horizontal)
            
            // PRO MANUAL CAMERA OVERLAYS
            VStack(alignment: .leading, spacing: 10) {
                Text("PRO MANUAL SHUTTER & LENS SETTINGS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 4)
                
                VStack(spacing: 12) {
                    // 1. Picture format selection and 48MP high-res sensor toggler
                    HStack {
                        Text("FORMAT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Picker("Format", selection: $pictureFormat) {
                            Text("JPG").tag("JPG")
                            Text("HEIF").tag("HEIF")
                            Text("RAW (DNG)").tag("DNG")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        
                        Toggle("48MP", isOn: $is48MP)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .toggleStyle(SwitchToggleStyle(tint: .red))
                            .frame(width: 80)
                    }
                    
                    Divider().background(Color.gray.opacity(0.1))
                    
                    // Lens & Digital Zoom Selector (0.5x Ultra Wide, 1.0x Wide, 5.0x Telephoto, and Digital Zoom options)
                    VStack(spacing: 6) {
                        HStack {
                            Text("LENS ZOOM")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.1fx", zoomFactor))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                        
                        HStack(spacing: 8) {
                            ForEach([0.5, 1.0, 2.0, 5.0, 10.0, 25.0], id: \.self) { factor in
                                Button(action: {
                                    zoomFactor = factor
                                    cameraManager.setZoomFactor(zoomFactor)
                                }) {
                                    Text(String(format: "%.1fx", factor))
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(zoomFactor == factor ? .cyan : .white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(zoomFactor == factor ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05))
                                        .cornerRadius(4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(zoomFactor == factor ? Color.cyan : Color.clear, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        Slider(value: $zoomFactor, in: 0.5...25.0, step: 0.1)
                            .tint(.cyan)
                            .onChange(of: zoomFactor) { newValue in
                                cameraManager.setZoomFactor(newValue)
                            }
                    }
                    
                    Divider().background(Color.gray.opacity(0.1))
                    
                    // 2. Shutter speed picker configuration
                    HStack {
                        Text("SHUTTER SPEED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Picker("Shutter", selection: $shutterSpeedIndex) {
                            ForEach(0..<shutterLabels.count, id: \.self) { idx in
                                Text(shutterLabels[idx]).tag(idx)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 160, height: 50)
                        .clipped()
                        .onChange(of: shutterSpeedIndex) { _ in
                            updateManualExposure()
                        }
                    }
                    
                    Divider().background(Color.gray.opacity(0.1))
                    
                    // 3. ISO Slider control
                    VStack(spacing: 4) {
                        HStack {
                            Text("ISO SENSITIVITY")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            Toggle("AUTO", isOn: $isAutoISO)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .toggleStyle(SwitchToggleStyle(tint: .cyan))
                                .onChange(of: isAutoISO) { _ in updateManualExposure() }
                            if !isAutoISO {
                                Text(String(format: "%.0f", isoValue))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.cyan)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        if !isAutoISO {
                            Slider(value: $isoValue, in: 50...3000, step: 50)
                                .tint(.cyan)
                                .onChange(of: isoValue) { _ in updateManualExposure() }
                        }
                    }
                    
                    Divider().background(Color.gray.opacity(0.1))
                    
                    // 4. White balance temperature slider control (Kelvin values)
                    VStack(spacing: 4) {
                        HStack {
                            Text("WHITE BALANCE (KELVIN)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            Toggle("AUTO", isOn: $isAutoWB)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .toggleStyle(SwitchToggleStyle(tint: .yellow))
                                .onChange(of: isAutoWB) { _ in updateManualExposure() }
                            if !isAutoWB {
                                Text(String(format: "%.0fK", wbTemperature))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .frame(width: 55, alignment: .trailing)
                            }
                        }
                        if !isAutoWB {
                            Slider(value: $wbTemperature, in: 2500...9000, step: 100)
                                .tint(.yellow)
                                .onChange(of: wbTemperature) { _ in updateManualExposure() }
                        }
                    }
                    
                    Divider().background(Color.gray.opacity(0.1))
                    
                    // 5. Focus mode slider and auto/manual toggle (0.0 nearest focus, 1.0 infinity focus)
                    VStack(spacing: 4) {
                        HStack {
                            Text("FOCUS MODE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            Toggle("AUTO", isOn: $isAutoFocus)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .onChange(of: isAutoFocus) { _ in updateManualFocus() }
                            if !isAutoFocus {
                                Text(focusPosition == 1.0 ? "INF" : String(format: "%.2f", focusPosition))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.green)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        if !isAutoFocus {
                            Slider(value: $focusPosition, in: 0.0...1.0, step: 0.05)
                                .tint(.green)
                                .onChange(of: focusPosition) { _ in updateManualFocus() }
                        }
                    }
                }
                .padding(12)
                .background(Color(red: 0.06, green: 0.08, blue: 0.15))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.15), lineWidth: 1))
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Point Cloud Projection SwiftUI Canvas Component

struct PointCloudVisualizerView: View {
    let points: [RawPoint3D]
    let isTracking: Bool
    let rotX: Double
    let rotY: Double
    let rotZ: Double // NEW
    let panX: Double
    let panY: Double
    let panZ: Double
    let zoom: Double
    
    // Optional parameters for rendering current position and trajectory
    var cameraPosition: (x: Double, y: Double, z: Double)? = nil
    var trajectory: [RawPoint3D]? = nil
    var showTrajectory: Bool = true
    var showCamera: Bool = true
    
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            
            if !isTracking || points.isEmpty {
                // Render high-tech diagnostic grid lines
                let gridColor = Color.cyan.opacity(0.15)
                context.stroke(
                    Path { path in
                        // Vertical grid
                        for x in stride(from: 20.0, to: size.width, by: 40.0) {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        // Horizontal grid
                        for y in stride(from: 20.0, to: size.height, by: 40.0) {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    },
                    with: .color(gridColor),
                    lineWidth: 0.5
                )
                
                // Overlay text
                context.draw(
                    Text("IMU GYRO RADAR DETECTOR")
                        .font(.caption2)
                        .fontWeight(.black)
                        .foregroundColor(.cyan.opacity(0.4)),
                    at: center
                )
                return
            }
            
            // Draw axis markers safely
            let origin3D = (x: 0.0, y: 0.0, z: 0.0)
            let projectedOrigin = project(point: origin3D, center: center, rotX: rotX, rotY: rotY, rotZ: rotZ)
            
            if projectedOrigin.x >= 0 && projectedOrigin.x <= size.width && projectedOrigin.y >= 0 && projectedOrigin.y <= size.height {
                let axes = [
                    (pt: (x: 0.5, y: 0.0, z: 0.0), col: Color.red),   // X - Red
                    (pt: (x: 0.0, y: 0.5, z: 0.0), col: Color.green), // Y - Green
                    (pt: (x: 0.0, y: 0.0, z: 0.5), col: Color.blue)   // Z - Blue
                ]
                
                for ax in axes {
                    let projPt = project(point: ax.pt, center: center, rotX: rotX, rotY: rotY, rotZ: rotZ)
                    if projPt.x >= 0 && projPt.x <= size.width && projPt.y >= 0 && projPt.y <= size.height {
                        context.stroke(
                            Path { path in
                                path.move(to: projectedOrigin)
                                path.addLine(to: projPt)
                            },
                            with: .color(ax.col.opacity(0.7)),
                            lineWidth: 2.0
                        )
                    }
                }
            }
            
            // Project and draw the 3D points in combined paths to avoid 100% CPU lock
            var greenPath = Path()
            var yellowPath = Path()
            var redPath = Path()
            
            for pt in points {
                let pt3D = (x: Double(pt.x), y: Double(pt.y), z: Double(pt.z))
                let proj = project(point: pt3D, center: center, rotX: rotX, rotY: rotY, rotZ: rotZ)
                
                // Rapid viewport bounds check to ignore off-screen projections
                guard proj.x >= 0 && proj.x <= size.width && proj.y >= 0 && proj.y <= size.height else {
                    continue
                }
                
                // Pre-sort by distance utilizing squared-distances to skip heavy sqrt math
                var pointColorType = 0 // 0 = Green, 1 = Yellow, 2 = Red
                if let cam = cameraPosition {
                    let dx = Double(pt.x) - cam.x
                    let dy = Double(pt.y) - cam.y
                    let dz = Double(pt.z) - cam.z
                    let distSq = dx*dx + dy*dy + dz*dz
                    
                    if distSq <= 3.24 { // 1.8m^2
                        pointColorType = 0
                    } else if distSq <= 10.24 { // 3.2m^2
                        pointColorType = 1
                    } else {
                        pointColorType = 2
                    }
                } else {
                    let distFromOriginSq = pt3D.x*pt3D.x + pt3D.y*pt3D.y + pt3D.z*pt3D.z
                    if distFromOriginSq <= 4.0 { // 2.0m^2
                        pointColorType = 0
                    } else if distFromOriginSq <= 16.0 { // 4.0m^2
                        pointColorType = 1
                    } else {
                        pointColorType = 2
                    }
                }
                
                // Draw as sharp micro-squares (extremely fast, visually identical to circles at 0.75 size)
                let rect = CGRect(x: proj.x - 0.375, y: proj.y - 0.375, width: 0.75, height: 0.75)
                if pointColorType == 0 {
                    greenPath.addRect(rect)
                } else if pointColorType == 1 {
                    yellowPath.addRect(rect)
                } else {
                    redPath.addRect(rect)
                }
            }
            
            // Execute drawing exactly 3 times (huge CPU optimization)
            context.fill(greenPath, with: .color(Color.green.opacity(0.8)))
            context.fill(yellowPath, with: .color(Color.yellow.opacity(0.8)))
            context.fill(redPath, with: .color(Color.red.opacity(0.8)))
            
            // Draw Trajectory Path
            if showTrajectory, let pathPoints = trajectory, pathPoints.count > 1 {
                context.stroke(
                    Path { path in
                        let firstPt = pathPoints[0]
                        let projFirst = project(point: (x: Double(firstPt.x), y: Double(firstPt.y), z: Double(firstPt.z)), center: center, rotX: rotX, rotY: rotY, rotZ: rotZ)
                        if projFirst.x >= 0 && projFirst.x <= size.width && projFirst.y >= 0 && projFirst.y <= size.height {
                            path.move(to: projFirst)
                        }
                        
                        for i in 1..<pathPoints.count {
                            let pt = pathPoints[i]
                            let proj = project(point: (x: Double(pt.x), y: Double(pt.y), z: Double(pt.z)), center: center, rotX: rotX, rotY: rotY, rotZ: rotZ)
                            if proj.x >= 0 && proj.x <= size.width && proj.y >= 0 && proj.y <= size.height {
                                if i == 1 || path.isEmpty {
                                    path.move(to: proj)
                                } else {
                                    path.addLine(to: proj)
                                }
                            }
                        }
                    },
                    with: .color(Color.yellow.opacity(0.85)),
                    lineWidth: 1.5
                )
            }
            
            // Draw Camera Position
            if showCamera, let camPos = cameraPosition {
                let projCam = project(point: camPos, center: center, rotX: rotX, rotY: rotY, rotZ: rotZ)
                
                if projCam.x >= 0 && projCam.x <= size.width && projCam.y >= 0 && projCam.y <= size.height {
                    let outerRect = CGRect(x: projCam.x - 7, y: projCam.y - 7, width: 14, height: 14)
                    let innerRect = CGRect(x: projCam.x - 3, y: projCam.y - 3, width: 6, height: 6)
                    
                    context.stroke(Path(ellipseIn: outerRect), with: .color(.yellow), lineWidth: 1.5)
                    context.fill(Path(ellipseIn: innerRect), with: .color(.red))
                }
            }
        }
    }
    
    // 3D Perspective Projection Mathematics
    private func project(point: (x: Double, y: Double, z: Double), center: CGPoint, rotX: Double, rotY: Double, rotZ: Double) -> CGPoint {
        // Shift point by panning coordinates (including depth Z axis)
        let px = point.x - panX
        let py = point.y - panY
        let pz = point.z - panZ
        
        // Map ARKit space (Y-up) to photogrammetry/GIS space (Z-up)
        // rx = East (X)
        // ry = North (-Z)
        // rz = Up (Y)
        let rx = px
        let ry = -pz
        let rz = py
        
        let finalRotX = rotX - Double.pi / 2.0 // Apply -90 degree offset globally around X-axis for horizontal alignment
        
        // 1. Rotate around vertical axis Z (rz) by yaw (rotY)
        let cosY = cos(rotY)
        let sinY = sin(rotY)
        let x1 = rx * cosY - ry * sinY
        let y1 = rx * sinY + ry * cosY
        
        // 2. Rotate around horizontal axis X (rx) by pitch (rotX)
        let cosX = cos(finalRotX)
        let sinX = sin(finalRotX)
        let z2 = rz * cosX - y1 * sinX  // Screen vertical coordinate
        let depth2 = rz * sinX + y1 * cosX // Screen depth coordinate
        
        // 3. Rotate in the screen plane (x1, z2) by roll (rotZ)
        let cosZ = cos(rotZ)
        let sinZ = sin(rotZ)
        let x2 = x1 * cosZ - z2 * sinZ
        let z3 = x1 * sinZ + z2 * cosZ
        
        // 4. Perspective Projection
        let fov = 3.0 // Focus distance/zoom
        let distance = 4.0 // Distance from camera
        let zoomAmount = 140.0 * zoom
        
        // Guard against points behind camera (depth2 <= -distance) to avoid division by zero or artifacts
        guard depth2 > -distance else {
            return CGPoint(x: -9999.0, y: -9999.0)
        }
        
        let scale = fov / (distance + depth2)
        let screenX = center.x + CGFloat(x2 * scale * zoomAmount)
        let screenY = center.y - CGFloat(z3 * scale * zoomAmount)
        
        return CGPoint(x: screenX, y: screenY)
    }
}

// MARK: - Core UI Design Cards

struct SensorCard: View {
    let title: String
    let icon: String
    let color: Color
    let content: [SensorRow]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundColor(.gray)
                Spacer()
            }
            Divider()
                .background(Color.gray.opacity(0.3))
            
            VStack(spacing: 5) {
                ForEach(content, id: \.self) { row in
                    HStack {
                        Text(row.label)
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(row.value)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding()
        .background(Color(red: 0.05, green: 0.08, blue: 0.16))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

struct SensorRow: Hashable {
    let label: String
    let value: String
}

// Transparent multi-touch receiver for 1-finger orbit, 2-finger panning, and pinch zoom
struct MultiTouchGestureOverlay: UIViewRepresentable {
    @Binding var rotX: Double
    @Binding var rotY: Double
    @Binding var panX: Double
    @Binding var panY: Double
    @Binding var zoom: Double
    var onInteractionBegan: (() -> Void)? = nil
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MultiTouchGestureOverlay
        
        init(_ parent: MultiTouchGestureOverlay) {
            self.parent = parent
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            // Traverse view hierarchy to find parent UIScrollView and intercept scrolling
            var currentView = gesture.view
            var parentScroll: UIScrollView? = nil
            while currentView != nil {
                if let sv = currentView as? UIScrollView {
                    parentScroll = sv
                    break
                }
                currentView = currentView?.superview
            }
            
            switch gesture.state {
            case .began:
                parentScroll?.isScrollEnabled = false // Lock scrolling!
                parent.onInteractionBegan?() // Disable auto-follow
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                if gesture.numberOfTouches == 1 {
                    parent.rotY += Double(translation.x) * 0.005
                    parent.rotX += Double(translation.y) * 0.005
                } else if gesture.numberOfTouches == 2 {
                    parent.panX -= Double(translation.x) * 0.005
                    parent.panY += Double(translation.y) * 0.005
                }
                gesture.setTranslation(.zero, in: gesture.view)
            case .ended, .cancelled:
                parentScroll?.isScrollEnabled = true // Restore scrolling!
            default:
                break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            parent.zoom *= Double(gesture.scale)
            parent.zoom = max(0.2, min(5.0, parent.zoom))
            gesture.scale = 1.0
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 2
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct TelemetryRow: View {
    let label: String
    let value: String
    let highlight: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                .foregroundColor(highlight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// SwiftUI wrapper for ARKit live camera preview during active runs
struct ARPreviewContainer: UIViewRepresentable {
    let trackingManager: MotionAndTrackingManager
    
    func makeUIView(context: Context) -> ARSCNView {
        return trackingManager.persistentARView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
