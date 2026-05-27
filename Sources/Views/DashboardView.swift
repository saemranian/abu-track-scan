import SwiftUI

struct DashboardView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var trackingManager: MotionAndTrackingManager
    
    @State private var sessionTimer: Timer?
    @State private var sessionDuration: TimeInterval = 0.0
    @State private var entryCount = 0
    @State private var activeSessionID: String?
    @State private var startTime: Date?
    
    // 3D Visualizer Drag Navigation State (Orbit, Pan, Zoom)
    @State private var rotX: Double = -0.4
    @State private var rotY: Double = 0.5
    @State private var panX: Double = 0.0
    @State private var panY: Double = 0.0
    @State private var zoom: Double = 1.0
    
    // Hardware Load Diagnostic State
    @State private var cpuUsage: Double = 0.0
    @State private var ramUsage: Double = 0.0
    @State private var hardwareTimer: Timer?
    
    // Toggles for Trajectory and Camera Position
    @State private var showTrajectory = true
    @State private var showCamera = true
    
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
                                        rotX: rotX,
                                        rotY: rotY,
                                        panX: panX,
                                        panY: panY,
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
                                        zoom: $zoom
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
                                    Button(action: {
                                        rotX = -0.4
                                        rotY = -trackingManager.yaw * Double.pi / 180.0
                                        panX = trackingManager.localX
                                        panY = trackingManager.localY
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
                                }
                                .padding(8)
                            }
                        }
                        .padding(.horizontal)
                        
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
                                    
                                    Text(trackingManager.isTrackingActive ? formatDuration(sessionDuration) : "STANDBY")
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
                                TelemetryRow(label: "SESSION TELEMETRY DATA", value: activeSessionID != nil ? "ID: \(String(activeSessionID!.suffix(8)))  [REC: \(entryCount)]" : "STREAM DISCONNECTED", highlight: .yellow)
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
            .navigationTitle("CAMTRACK PRO")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            locationManager.isGPSEnabled = RigSettings.isGPSEnabled
            
            // Periodic Hardware Diagnostics Timer (CPU / RAM Load monitoring)
            hardwareTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.cpuUsage = getCPUUsage()
                self.ramUsage = getMemoryUsage().used
            }
        }
        .onDisappear {
            hardwareTimer?.invalidate()
            hardwareTimer = nil
        }
    }
    
    // MARK: - Session Controllers
    
    private func startSession() {
        let sessionID = TelemetryLogger.shared.startNewSession()
        self.activeSessionID = sessionID
        self.startTime = Date()
        self.entryCount = 0
        self.sessionDuration = 0.0
        
        // Start physical managers
        locationManager.startUpdates()
        trackingManager.startTracking(frequency: RigSettings.captureRate)
        
        // Automatically snap viewport to active camera coordinate
        self.panX = trackingManager.localX
        self.panY = trackingManager.localY
        self.rotY = -trackingManager.yaw * Double.pi / 180.0
        
        // UI Timer updates
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let start = self.startTime else { return }
            self.sessionDuration = Date().timeIntervalSince(start)
            
            // Log Telemetry Record
            let entry = TelemetryEntry(
                timestamp: Date().timeIntervalSince1970 * 1000.0,
                localX: trackingManager.localX,
                localY: trackingManager.localY,
                localZ: trackingManager.localZ,
                relativeAltitude: trackingManager.relativeAltitude,
                pressure: trackingManager.pressureInKPa,
                pitch: trackingManager.pitch,
                roll: trackingManager.roll,
                yaw: trackingManager.yaw,
                q_w: trackingManager.q_w,
                q_x: trackingManager.q_x,
                q_y: trackingManager.q_y,
                q_z: trackingManager.q_z,
                isGPSEnabled: locationManager.isGPSEnabled,
                latitude: locationManager.latitude,
                longitude: locationManager.longitude,
                gpsAltitude: locationManager.altitude,
                horizontalAccuracy: locationManager.horizontalAccuracy,
                verticalAccuracy: locationManager.verticalAccuracy
            )
            
            TelemetryLogger.shared.log(entry)
            self.entryCount += 1
        }
    }
    
    private func stopSession() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        
        // Write details to history index in UserDefaults
        if let sessionID = activeSessionID, let start = startTime {
            let sessionInfo: [String: Any] = [
                "id": sessionID,
                "startTime": start.timeIntervalSince1970,
                "endTime": Date().timeIntervalSince1970,
                "entryCount": entryCount,
                "isGPSEnabled": locationManager.isGPSEnabled
            ]
            
            var history = UserDefaults.standard.array(forKey: "sessionHistory") as? [[String: Any]] ?? []
            history.insert(sessionInfo, at: 0)
            UserDefaults.standard.set(history, forKey: "sessionHistory")
        }
        
        trackingManager.stopTracking()
        locationManager.stopUpdates()
        TelemetryLogger.shared.stopSession(sparsePointCloud: trackingManager.accumulatedPointCloud)
        
        self.activeSessionID = nil
        self.startTime = nil
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
            
            let usedMB = usedBytes / 1024.0 / 1024.0
            let totalGB = totalBytes / 1024.0 / 1024.0 / 1024.0
            
            let pct = (usedBytes / totalBytes) * 100.0
            return (used: pct, total: totalGB)
        }
        
        return (used: 0.0, total: 0.0)
    }
}

// MARK: - Point Cloud Projection SwiftUI Canvas Component

struct PointCloudVisualizerView: View {
    let points: [RawPoint3D]
    let isTracking: Bool
    let rotX: Double
    let rotY: Double
    let panX: Double
    let panY: Double
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
            
            // Draw axis markers
            let origin3D = (x: 0.0, y: 0.0, z: 0.0)
            let projectedOrigin = project(point: origin3D, center: center, rotX: rotX, rotY: rotY)
            
            let axes = [
                (pt: (x: 0.5, y: 0.0, z: 0.0), col: Color.red),   // X - Red
                (pt: (x: 0.0, y: 0.5, z: 0.0), col: Color.green), // Y - Green
                (pt: (x: 0.0, y: 0.0, z: 0.5), col: Color.blue)   // Z - Blue
            ]
            
            for ax in axes {
                let projPt = project(point: ax.pt, center: center, rotX: rotX, rotY: rotY)
                context.stroke(
                    Path { path in
                        path.move(to: projectedOrigin)
                        path.addLine(to: projPt)
                    },
                    with: .color(ax.col.opacity(0.7)),
                    lineWidth: 2.0
                )
            }
            
            // Project and draw the 3D points
            for pt in points {
                let pt3D = (x: Double(pt.x), y: Double(pt.y), z: Double(pt.z))
                let proj = project(point: pt3D, center: center, rotX: rotX, rotY: rotY)
                
                // Determine color based on reconstruction depth quality (distance from camera)
                var pointColor = Color.green
                if let cam = cameraPosition {
                    let dx = Double(pt.x) - cam.x
                    let dy = Double(pt.y) - cam.y
                    let dz = Double(pt.z) - cam.z
                    let dist = sqrt(dx*dx + dy*dy + dz*dz)
                    
                    if dist <= 1.8 {
                        pointColor = .green
                    } else if dist <= 3.2 {
                        pointColor = .yellow
                    } else {
                        pointColor = .red
                    }
                } else {
                    let distFromOrigin = sqrt(pt3D.x*pt3D.x + pt3D.y*pt3D.y + pt3D.z*pt3D.z)
                    if distFromOrigin <= 2.0 {
                        pointColor = .green
                    } else if distFromOrigin <= 4.0 {
                        pointColor = .yellow
                    } else {
                        pointColor = .red
                    }
                }
                
                // Draw each point as a glowing particle (4x smaller: width 0.75, height 0.75)
                let rect = CGRect(x: proj.x - 0.375, y: proj.y - 0.375, width: 0.75, height: 0.75)
                context.fill(Path(ellipseIn: rect), with: .color(pointColor.opacity(0.8)))
            }
            
            // Draw Trajectory Path
            if showTrajectory, let pathPoints = trajectory, pathPoints.count > 1 {
                context.stroke(
                    Path { path in
                        let firstPt = pathPoints[0]
                        let projFirst = project(point: (x: Double(firstPt.x), y: Double(firstPt.y), z: Double(firstPt.z)), center: center, rotX: rotX, rotY: rotY)
                        path.move(to: projFirst)
                        
                        for i in 1..<pathPoints.count {
                            let pt = pathPoints[i]
                            let proj = project(point: (x: Double(pt.x), y: Double(pt.y), z: Double(pt.z)), center: center, rotX: rotX, rotY: rotY)
                            path.addLine(to: proj)
                        }
                    },
                    with: .color(Color.yellow.opacity(0.85)),
                    lineWidth: 1.5
                )
            }
            
            // Draw Camera Position
            if showCamera, let camPos = cameraPosition {
                let projCam = project(point: camPos, center: center, rotX: rotX, rotY: rotY)
                
                let outerRect = CGRect(x: projCam.x - 7, y: projCam.y - 7, width: 14, height: 14)
                let innerRect = CGRect(x: projCam.x - 3, y: projCam.y - 3, width: 6, height: 6)
                
                context.stroke(Path(ellipseIn: outerRect), with: .color(.yellow), lineWidth: 1.5)
                context.fill(Path(ellipseIn: innerRect), with: .color(.red))
            }
        }
    }
    
    // 3D Perspective Projection Mathematics
    private func project(point: (x: Double, y: Double, z: Double), center: CGPoint, rotX: Double, rotY: Double) -> CGPoint {
        // Shift point by panning coordinates
        let px = point.x - panX
        let py = point.y - panY
        let pz = point.z
        
        // 1. Rotate around Y-axis
        let cosY = cos(rotY)
        let sinY = sin(rotY)
        let x1 = px * cosY - pz * sinY
        let z1 = px * sinY + pz * cosY
        
        // 2. Rotate around X-axis
        let cosX = cos(rotX)
        let sinX = sin(rotX)
        let y2 = py * cosX - z1 * sinX
        let z2 = py * sinX + z1 * cosX
        
        // 3. Perspective Projection
        let fov = 3.0 // Focus distance/zoom
        let distance = 4.0 // Distance from camera
        let zoomAmount = 140.0 * zoom
        
        let scale = fov / (fov + z2 + distance)
        let screenX = center.x + CGFloat(x1 * scale * zoomAmount)
        let screenY = center.y - CGFloat(y2 * scale * zoomAmount)
        
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
    
    class Coordinator: NSObject {
        var parent: MultiTouchGestureOverlay
        
        init(_ parent: MultiTouchGestureOverlay) {
            self.parent = parent
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            
            if gesture.numberOfTouches == 1 {
                // 1-finger orbit
                parent.rotY += Double(translation.x) * 0.005
                parent.rotX += Double(translation.y) * 0.005
            } else if gesture.numberOfTouches == 2 {
                // 2-finger translation pan
                parent.panX -= Double(translation.x) * 0.005
                parent.panY += Double(translation.y) * 0.005
            }
            
            gesture.setTranslation(.zero, in: gesture.view)
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
