import SwiftUI

struct DashboardView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var trackingManager: MotionAndTrackingManager
    
    @State private var sessionTimer: Timer?
    @State private var sessionDuration: TimeInterval = 0.0
    @State private var entryCount = 0
    @State private var activeSessionID: String?
    @State private var startTime: Date?
    
    // 3D Visualizer Drag Rotation State
    @State private var rotX: Double = -0.4
    @State private var rotY: Double = 0.5
    @GestureState private var dragOffset = CGSize.zero
    
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
                    VStack(spacing: 20) {
                        
                        // Interactive 3D Point Cloud Coverage Map
                        VStack(spacing: 5) {
                            HStack {
                                Label("Live 3D Coverage Point Cloud", systemImage: "circle.grid.3x3.fill")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.cyan)
                                Spacer()
                                Text(trackingManager.isTrackingActive ? "\(trackingManager.sparsePointCloud.count) points" : "Inactive")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 15)
                            .padding(.top, 10)
                            
                            // Visualizer Box
                            PointCloudVisualizerView(
                                points: trackingManager.sparsePointCloud,
                                isTracking: trackingManager.isTrackingActive,
                                rotX: rotX + Double(dragOffset.height) * 0.01,
                                rotY: rotY + Double(dragOffset.width) * 0.01
                            )
                            .frame(height: 220)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                            )
                            .gesture(
                                DragGesture()
                                    .updating($dragOffset) { value, state, _ in
                                        state = value.translation
                                    }
                                    .onEnded { value in
                                        rotX += Double(value.translation.height) * 0.01
                                        rotY += Double(value.translation.width) * 0.01
                                    }
                            )
                        }
                        .padding(.horizontal)
                        
                        // Active Record Button Grid
                        HStack(spacing: 15) {
                            // Start/Stop Record Button
                            Button(action: {
                                if trackingManager.isTrackingActive {
                                    stopSession()
                                } else {
                                    startSession()
                                }
                            }) {
                                HStack {
                                    ZStack {
                                        Circle()
                                            .fill(trackingManager.isTrackingActive ? Color.red.opacity(0.2) : Color.cyan.opacity(0.2))
                                            .frame(width: 42, height: 42)
                                        
                                        Circle()
                                            .fill(trackingManager.isTrackingActive ? Color.red : Color.cyan)
                                            .frame(width: 18, height: 18)
                                            .scaleEffect(trackingManager.isTrackingActive ? 1.2 : 1.0)
                                            .animation(trackingManager.isTrackingActive ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: trackingManager.isTrackingActive)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(trackingManager.isTrackingActive ? "STOP LOGGING" : "START LOGGING")
                                            .font(.footnote)
                                            .fontWeight(.heavy)
                                            .foregroundColor(.white)
                                        Text(trackingManager.isTrackingActive ? formatDuration(sessionDuration) : "Ready to record")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(red: 0.05, green: 0.08, blue: 0.18))
                                        .shadow(color: trackingManager.isTrackingActive ? Color.red.opacity(0.15) : Color.cyan.opacity(0.15), radius: 10, x: 0, y: 4)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(trackingManager.isTrackingActive ? Color.red.opacity(0.3) : Color.cyan.opacity(0.3), lineWidth: 1)
                                )
                            }
                            
                            // GPS Mode Toggle Button
                            Button(action: {
                                RigSettings.isGPSEnabled.toggle()
                                locationManager.isGPSEnabled = RigSettings.isGPSEnabled
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: locationManager.isGPSEnabled ? "location.fill" : "location.slash")
                                        .font(.title3)
                                        .foregroundColor(locationManager.isGPSEnabled ? .green : .orange)
                                    
                                    Text(locationManager.isGPSEnabled ? "GPS ON (Outdoor)" : "GPS OFF (Indoor)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                .frame(width: 100, height: 76)
                                .background(Color(red: 0.05, green: 0.08, blue: 0.18))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(locationManager.isGPSEnabled ? Color.green.opacity(0.2) : Color.orange.opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Live Diagnostics Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                            
                            // Card 1: GPS Diagnostics
                            SensorCard(
                                title: "GPS System (RTK Enabled)",
                                icon: "location.fill",
                                color: locationManager.isGPSEnabled ? .green : .orange,
                                content: [
                                    SensorRow(label: "Status", value: locationManager.isGPSEnabled ? "Active" : "Disabled (Indoor)"),
                                    SensorRow(label: "Lat", value: locationManager.isGPSEnabled ? String(format: "%.6f", locationManager.latitude) : "N/A"),
                                    SensorRow(label: "Lon", value: locationManager.isGPSEnabled ? String(format: "%.6f", locationManager.longitude) : "N/A"),
                                    SensorRow(label: "Precision", value: locationManager.isGPSEnabled ? String(format: "±%.1fm", locationManager.horizontalAccuracy) : "N/A")
                                ]
                            )
                            
                            // Card 2: IMU Sensor Fusion
                            SensorCard(
                                title: "CoreMotion IMU Hub",
                                icon: "gyroscope",
                                color: .cyan,
                                content: [
                                    SensorRow(label: "State", value: trackingManager.appState.contains("Background") ? "BG Logger" : "VIO Active"),
                                    SensorRow(label: "Yaw", value: String(format: "%.1f°", trackingManager.yaw)),
                                    SensorRow(label: "Pitch", value: String(format: "%.1f°", trackingManager.pitch)),
                                    SensorRow(label: "Roll", value: String(format: "%.1f°", trackingManager.roll))
                                ]
                            )
                            
                            // Card 3: Barometric Altimeter
                            SensorCard(
                                title: "Barometric Altimeter",
                                icon: "barometer",
                                color: .purple,
                                content: [
                                    SensorRow(label: "State", value: trackingManager.barometerActive ? "Polling" : "No Baro"),
                                    SensorRow(label: "Relative Height", value: String(format: "%+.2fm", trackingManager.relativeAltitude)),
                                    SensorRow(label: "Pressure", value: String(format: "%.3fkPa", trackingManager.pressureInKPa)),
                                    SensorRow(label: "Calibration", value: trackingManager.magneticCalibration)
                                ]
                            )
                            
                            // Card 4: Session Metrics
                            SensorCard(
                                title: "Active Logging Stats",
                                icon: "doc.text.fill",
                                color: .yellow,
                                content: [
                                    SensorRow(label: "Active ID", value: activeSessionID != nil ? String(activeSessionID!.suffix(8)) : "None"),
                                    SensorRow(label: "Records", value: "\(entryCount)"),
                                    SensorRow(label: "VIO Coords", value: String(format: "%.1f, %.1f, %.1f", trackingManager.localX, trackingManager.localY, trackingManager.localZ)),
                                    SensorRow(label: "Rate Setting", value: String(format: "%.0fHz", RigSettings.captureRate))
                                ]
                            )
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("CAMTRACK PRO")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            locationManager.isGPSEnabled = RigSettings.isGPSEnabled
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
        TelemetryLogger.shared.stopSession(sparsePointCloud: trackingManager.sparsePointCloud)
        
        self.activeSessionID = nil
        self.startTime = nil
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        let tenths = Int((interval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Point Cloud Projection SwiftUI Canvas Component

struct PointCloudVisualizerView: View {
    let points: [RawPoint3D]
    let isTracking: Bool
    let rotX: Double
    let rotY: Double
    
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
                
                // Draw each point as a glowing particle
                let rect = CGRect(x: proj.x - 1.5, y: proj.y - 1.5, width: 3, height: 3)
                context.fill(Path(ellipseIn: rect), with: .color(.cyan.opacity(0.8)))
            }
        }
    }
    
    // 3D Perspective Projection Mathematics
    private func project(point: (x: Double, y: Double, z: Double), center: CGPoint, rotX: Double, rotY: Double) -> CGPoint {
        // 1. Rotate around Y-axis
        let cosY = cos(rotY)
        let sinY = sin(rotY)
        let x1 = point.x * cosY - point.z * sinY
        let z1 = point.x * sinY + point.z * cosY
        
        // 2. Rotate around X-axis
        let cosX = cos(rotX)
        let sinX = sin(rotX)
        let y2 = point.y * cosX - z1 * sinX
        let z2 = point.y * sinX + z1 * cosX
        
        // 3. Perspective Projection
        let fov = 3.0 // Focus distance/zoom
        let distance = 4.0 // Distance from camera
        let zoom = 140.0
        
        let scale = fov / (fov + z2 + distance)
        let screenX = center.x + CGFloat(x1 * scale * zoom)
        let screenY = center.y - CGFloat(y2 * scale * zoom)
        
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
                for row in content {
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
