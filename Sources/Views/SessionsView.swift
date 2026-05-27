import SwiftUI

struct SessionsView: View {
    @State private var sessions: [[String: Any]] = []
    @State private var selectedSession: [String: Any]?
    
    struct SessionListItem: Identifiable {
        let id: String
        let entries: Int
        let isGPS: Bool
        let startTime: Date
        let rawSession: [String: Any]
    }
    
    private var sessionListItems: [SessionListItem] {
        sessions.compactMap { sess in
            guard let id = sess["id"] as? String else { return nil }
            let entries = sess["entryCount"] as? Int ?? 0
            let isGPS = sess["isGPSEnabled"] as? Bool ?? true
            let startTime = Date(timeIntervalSince1970: sess["startTime"] as? Double ?? 0.0)
            return SessionListItem(id: id, entries: entries, isGPS: isGPS, startTime: startTime, rawSession: sess)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.02, green: 0.03, blue: 0.08)
                    .ignoresSafeArea()
                
                if sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.minus")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No capture sessions found")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    List {
                        ForEach(sessionListItems) { item in
                            Button(action: {
                                self.selectedSession = item.rawSession
                                self.selectedSessionItem = IdentifiableSession(id: item.id, session: item.rawSession)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Session \(item.id)")
                                            .font(.footnote)
                                            .fontWeight(.black)
                                            .foregroundColor(.white)
                                        
                                        HStack(spacing: 12) {
                                            Label("\(item.entries) pts", systemImage: "circle.grid.3x3.fill")
                                            Label(item.isGPS ? "GPS+IMU" : "Pure VIO", systemImage: item.isGPS ? "location.fill" : "location.slash")
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 6) {
                                        Text(formatDate(item.startTime))
                                            .font(.caption2)
                                            .foregroundColor(.cyan)
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color(red: 0.05, green: 0.08, blue: 0.16))
                        }
                        .onDelete(perform: deleteSession)
                    }
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("SESSION LOGS")
            .sheet(item: $selectedSessionItem, onDismiss: {
                self.selectedSession = nil
            }) { item in
                SessionDetailView(session: item.session) {
                    loadHistory()
                }
            }
            .onAppear {
                loadHistory()
            }
        }
    }
    
    // Binding helper to allow sheets in SwiftUI
    struct IdentifiableSession: Identifiable {
        let id: String
        let session: [String: Any]
    }
    
    @State private var selectedSessionItem: IdentifiableSession?
    
    private var selectedSessionBinding: Binding<IdentifiableSession?> {
        Binding(
            get: {
                if let sess = selectedSession {
                    let id = sess["id"] as? String ?? ""
                    return IdentifiableSession(id: id, session: sess)
                }
                return nil
            },
            set: { val in
                selectedSession = val?.session
            }
        )
    }
    
    private func loadHistory() {
        self.sessions = UserDefaults.standard.array(forKey: "sessionHistory") as? [[String: Any]] ?? []
        // Sync binding to open sheets correctly
        if let sess = selectedSession {
            let id = sess["id"] as? String ?? ""
            selectedSessionItem = IdentifiableSession(id: id, session: sess)
        }
    }
    
    private func deleteSession(at offsets: IndexSet) {
        var history = UserDefaults.standard.array(forKey: "sessionHistory") as? [[String: Any]] ?? []
        
        for index in offsets {
            let sess = history[index]
            if let id = sess["id"] as? String {
                // Delete actual files inside the directory
                let fileManager = FileManager.default
                if let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let folderURL = docURL.appendingPathComponent("Sessions").appendingPathComponent(id)
                    try? fileManager.removeItem(at: folderURL)
                }
            }
        }
        
        history.remove(atOffsets: offsets)
        UserDefaults.standard.set(history, forKey: "sessionHistory")
        loadHistory()
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Detailed Subview for Syncing and Exporting files

struct SessionDetailView: View {
    let session: [String: Any]
    let onUpdate: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var syncManager = PhotoSyncManager.shared
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // Dynamic export URLs
    @State private var csvURL: URL?
    @State private var metashapeCSVURL: URL?
    @State private var plyURL: URL?
    
    // 3D Historical Map variables
    @State private var historicalPoints: [RawPoint3D] = []
    @State private var historicalTrajectory: [RawPoint3D] = []
    @State private var loading3DData = false
    @State private var rotX: Double = -0.5
    @State private var rotY: Double = 0.5
    @State private var panX: Double = 0.0
    @State private var panY: Double = 0.0
    @State private var zoom: Double = 1.0
    @State private var showTrajectory = true
    @State private var showCamera = true
    
    private var id: String { session["id"] as? String ?? "" }
    private var entries: Int { session["entryCount"] as? Int ?? 0 }
    private var isGPS: Bool { session["isGPSEnabled"] as? Bool ?? true }
    private var start: Date { Date(timeIntervalSince1970: session["startTime"] as? Double ?? 0.0) }
    private var end: Date { Date(timeIntervalSince1970: session["endTime"] as? Double ?? 0.0) }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.02, green: 0.03, blue: 0.08)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        detailsCard
                        historicalMapCard
                        syncControlsCard
                        exportLinksCard
                        matchedPhotosCard
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("SESSION MANAGER")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                checkFilesExist()
                loadHistorical3DData()
            }
            .alert("Post Processing", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    @ViewBuilder
    private var detailsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Session Details")
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundColor(.cyan)
                Spacer()
            }
            Divider().background(Color.gray.opacity(0.3))
            
            DetailRow(label: "Identifier", value: id)
            DetailRow(label: "Duration", value: String(format: "%.1fs", end.timeIntervalSince(start)))
            DetailRow(label: "Sensor Entries", value: "\(entries) pts")
            DetailRow(label: "GPS Tracking", value: isGPS ? "GPS + IMU Enabled" : "Pure Inertial/Baro Indoor Mode")
        }
        .padding()
        .background(Color(red: 0.05, green: 0.08, blue: 0.16))
        .cornerRadius(14)
        .padding(.horizontal)
        .padding(.top, 15)
    }
    
    @ViewBuilder
    private var syncControlsCard: some View {
        VStack(spacing: 15) {
            Button(action: triggerPhotosSync) {
                HStack {
                    if syncManager.isSyncing {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                    }
                    Text(syncManager.isSyncing ? "SYNCING..." : "SYNC CAMERA IMAGES")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(syncManager.isSyncing ? Color.cyan.opacity(0.4) : Color.cyan)
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: Color.cyan.opacity(0.2), radius: 6, x: 0, y: 3)
            }
            .disabled(syncManager.isSyncing)
            
            if !syncManager.syncMessage.isEmpty {
                Text(syncManager.syncMessage)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var exportLinksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export References")
                .font(.caption)
                .fontWeight(.black)
                .foregroundColor(.cyan)
                .padding(.horizontal)
            
            HStack(spacing: 15) {
                // Link 1: Metashape Sync Output
                if let url = metashapeCSVURL {
                    ShareLink(item: url) {
                        Label("Metashape CSV", systemImage: "arrow.up.doc")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.4), lineWidth: 1))
                    }
                }
                
                // Link 2: 3D Point Cloud PLY
                if let url = plyURL {
                    ShareLink(item: url) {
                        Label("PLY Cloud", systemImage: "square.stack.3d.up.fill")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.4), lineWidth: 1))
                    }
                }
                
                // Link 3: Raw telemetry logs (30Hz)
                if let url = csvURL {
                    ShareLink(item: url) {
                        Label("Raw Logs", systemImage: "doc.text")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.yellow.opacity(0.2))
                            .foregroundColor(.yellow)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.4), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var matchedPhotosCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Matched Images Grid (\(syncManager.matchedRecords.count))")
                .font(.caption)
                .fontWeight(.black)
                .foregroundColor(.cyan)
                .padding(.horizontal)
            
            if syncManager.matchedRecords.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Perform sync to match default library photos")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    Spacer()
                }
                .frame(height: 100)
                .background(Color.black.opacity(0.2))
                .cornerRadius(10)
                .padding(.horizontal)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(syncManager.matchedRecords) { rec in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rec.imageName)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    Text(String(format: "Local VIO: %.2f, %.2f, %.2f m", rec.localX, rec.localY, rec.localZ))
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(String(format: "Yaw: %.1f°", rec.yaw))
                                        .font(.caption2)
                                        .foregroundColor(.cyan)
                                    Text(String(format: "Diff: %+.2fs", rec.timeDifferenceSec))
                                        .font(.caption2)
                                        .foregroundColor(abs(rec.timeDifferenceSec) > 0.5 ? .orange : .gray)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.04, green: 0.06, blue: 0.12))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private var historicalMapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("3D Reconstructed Map & Path")
                .font(.caption)
                .fontWeight(.black)
                .foregroundColor(.cyan)
                .padding(.horizontal)
            
            if loading3DData {
                VStack {
                    ProgressView()
                        .tint(.cyan)
                    Text("Loading 3D telemetry cloud...")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.top, 4)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.2))
                .cornerRadius(12)
                .padding(.horizontal)
            } else if historicalPoints.isEmpty && historicalTrajectory.isEmpty {
                VStack {
                    Image(systemName: "circle.slash")
                        .font(.title)
                        .foregroundColor(.gray)
                    Text("No 3D spatial points logged in this session")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.top, 4)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.2))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                ZStack(alignment: .bottomTrailing) {
                    // Interactive 3D Canvas with Multi-Touch Overlay
                    ZStack {
                        PointCloudVisualizerView(
                            points: historicalPoints,
                            isTracking: true,
                            rotX: rotX,
                            rotY: rotY,
                            panX: panX,
                            panY: panY,
                            zoom: zoom,
                            cameraPosition: historicalTrajectory.last.map { (x: Double($0.x), y: Double($0.y), z: Double($0.z)) },
                            trajectory: historicalTrajectory,
                            showTrajectory: showTrajectory,
                            showCamera: showCamera
                        )
                        
                        // Transparent multi-touch overlay
                        MultiTouchGestureOverlay(
                            rotX: $rotX,
                            rotY: $rotY,
                            panX: $panX,
                            panY: $panY,
                            zoom: $zoom
                        )
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(12)
                    
                    // Interactive Buttons
                    HStack(spacing: 8) {
                        Button(action: { showTrajectory.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: showTrajectory ? "point.topleft.down.to.point.bottomright.curvepath" : "point.topleft.down.to.point.bottomright.curvepath.fill")
                                Text("PATH")
                            }
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(showTrajectory ? .yellow : .gray)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(showTrajectory ? Color.yellow.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        Button(action: { showCamera.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: showCamera ? "camera.fill" : "camera")
                                Text("CAM")
                            }
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(showCamera ? .red : .gray)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(showCamera ? Color.red.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(8)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func loadHistorical3DData() {
        guard let csvURL = csvURL else { return }
        loading3DData = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var loadedPoints: [RawPoint3D] = []
            var loadedTrajectory: [RawPoint3D] = []
            
            // 1. Try to load points from PLY if exists
            if let plyURL = plyURL,
               let plyString = try? String(contentsOf: plyURL, encoding: .utf8) {
                let lines = plyString.components(separatedBy: .newlines)
                var headerPassed = false
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    if trimmed == "end_header" {
                        headerPassed = true
                        continue
                    }
                    if headerPassed {
                        let comps = trimmed.components(separatedBy: .whitespaces)
                        if comps.count >= 3,
                           let x = Float(comps[0]),
                           let y = Float(comps[1]),
                           let z = Float(comps[2]) {
                            loadedPoints.append(RawPoint3D(x: x, y: y, z: z))
                        }
                    }
                }
            }
            
            // 2. Load trajectory from CSV
            if let csvString = try? String(contentsOf: csvURL, encoding: .utf8) {
                let lines = csvString.components(separatedBy: .newlines)
                var isFirst = true
                var step = 0
                for line in lines {
                    if isFirst {
                        isFirst = false
                        continue
                    }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    
                    step += 1
                    // Read every 15th line to keep rendering fast
                    if step % 15 == 0 {
                        let comps = trimmed.components(separatedBy: ",")
                        if comps.count >= 4,
                           let tx = Float(comps[1]),
                           let ty = Float(comps[2]),
                           let tz = Float(comps[3]) {
                            loadedTrajectory.append(RawPoint3D(x: tx, y: ty, z: tz))
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.historicalPoints = loadedPoints
                self.historicalTrajectory = loadedTrajectory
                self.loading3DData = false
            }
        }
    }
    
    private func checkFilesExist() {
        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let sessionFolder = docURL.appendingPathComponent("Sessions").appendingPathComponent(id)
        
        let fileCSV = sessionFolder.appendingPathComponent("telemetry_log.csv")
        if fileManager.fileExists(atPath: fileCSV.path) {
            csvURL = fileCSV
        }
        
        let fileMetashape = sessionFolder.appendingPathComponent("metashape_cameras.csv")
        if fileManager.fileExists(atPath: fileMetashape.path) {
            metashapeCSVURL = fileMetashape
            // Attempt to parse matched records already stored in CSV
            parseExistingMetashapeCSV(url: fileMetashape)
        }
        
        let filePLY = sessionFolder.appendingPathComponent("coverage_cloud.ply")
        if fileManager.fileExists(atPath: filePLY.path) {
            plyURL = filePLY
        }
    }
    
    private func triggerPhotosSync() {
        // Read Rig calibration parameters from RigSettings
        let lx = RigSettings.leverArmX
        let ly = RigSettings.leverArmY
        let lz = RigSettings.leverArmZ
        
        syncManager.syncPhotos(
            sessionID: id,
            startTime: start,
            endTime: end,
            leverArmX: lx,
            leverArmY: ly,
            leverArmZ: lz
        ) { success, message in
            DispatchQueue.main.async {
                alertMessage = message
                showAlert = true
                checkFilesExist()
                onUpdate()
            }
        }
    }
    
    private func parseExistingMetashapeCSV(url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        var temp: [SyncedPhotoRecord] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: ",")
            if cols.count < 12 { continue }
            
            let label = cols[0]
            guard let lx = Double(cols[1]),
                  let ly = Double(cols[2]),
                  let lz = Double(cols[3]),
                  let baro = Double(cols[4]),
                  let lat = Double(cols[5]),
                  let lon = Double(cols[6]),
                  let gpsAlt = Double(cols[7]),
                  let yaw = Double(cols[8]),
                  let pitch = Double(cols[9]),
                  let roll = Double(cols[10]),
                  let timeDiff = Double(cols[11]) else { continue }
            
            let rec = SyncedPhotoRecord(
                imageName: label,
                timestamp: 0.0,
                localX: lx,
                localY: ly,
                localZ: lz,
                baroAlt: baro,
                pitch: pitch,
                roll: roll,
                yaw: yaw,
                latitude: lat,
                longitude: lon,
                gpsAltitude: gpsAlt,
                timeDifferenceSec: timeDiff
            )
            temp.append(rec)
        }
        
        DispatchQueue.main.async {
            self.syncManager.matchedRecords = temp.sorted { $0.imageName < $1.imageName }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}
