import SwiftUI

struct SessionsView: View {
    @State private var sessions: [[String: Any]] = []
    @State private var selectedSession: [String: Any]?
    
    // States for Renaming sessions
    @State private var showRenameAlert = false
    @State private var sessionToRename: String?
    @State private var renameInputText = ""
    
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
                ProTheme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(ProTheme.accentCyan)
                        Text("RECORDED SESSIONS & EXPORTS")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(ProTheme.textPrimary)
                        Spacer()
                        Text("\(sessions.count) Takes")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(ProTheme.accentCyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ProTheme.cardBackground)
                            .cornerRadius(6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    WorkflowStepBanner(
                        stepsText: "① Tap a take  →  ② Sync DSLR Photos (SLERP + Slate)  →  ③ Export .abuscan.json / COLMAP",
                        helpTopic: .sessionsSync
                    )
                    .padding(.horizontal, 16)

                    if sessions.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 42))
                                .foregroundColor(ProTheme.accentCyan.opacity(0.6))
                            Text("No Recorded Takes Yet")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(ProTheme.textPrimary)
                            Text("Go to 'Track & Scan' and tap 'START CAPTURE' to record 60Hz VIO poses, LiDAR depth (.PLY/.PTS), and timecode-synced photos.")
                                .font(.system(size: 12))
                                .foregroundColor(ProTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 36)
                        }
                        Spacer()
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
                                .listRowBackground(ProTheme.cardBackground)
                                .contextMenu {
                                    Button {
                                        self.sessionToRename = item.id
                                        self.renameInputText = item.id
                                        self.showRenameAlert = true
                                    } label: {
                                        Label("Rename Session", systemImage: "pencil")
                                    }
                                    
                                    Button(role: .destructive) {
                                        if let idx = sessions.firstIndex(where: { ($0["id"] as? String) == item.id }) {
                                            deleteSession(at: IndexSet(integer: idx))
                                        }
                                    } label: {
                                        Label("Delete Session", systemImage: "trash")
                                    }
                                }
                            }
                            .onDelete(perform: deleteSession)
                        }
                        .background(Color.clear)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationBarHidden(true)
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
            .alert("Rename Session", isPresented: $showRenameAlert) {
                TextField("New Session Name", text: $renameInputText)
                Button("Rename") {
                    if let id = sessionToRename {
                        renameSession(id: id, newName: renameInputText)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a new identifier for this capture session.")
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
    
    private func renameSession(id: String, newName: String) {
        var history = UserDefaults.standard.array(forKey: "sessionHistory") as? [[String: Any]] ?? []
        guard let index = history.firstIndex(where: { ($0["id"] as? String) == id }) else { return }
        
        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        // Sanitize new name (allow alphanumerics, hyphens, underscores)
        let sanitized = newName
            .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "-_")))
            .joined()
        
        if sanitized.isEmpty { return }
        
        let oldFolderURL = docURL.appendingPathComponent("Sessions").appendingPathComponent(id)
        let newFolderURL = docURL.appendingPathComponent("Sessions").appendingPathComponent(sanitized)
        
        do {
            if fileManager.fileExists(atPath: oldFolderURL.path) {
                try fileManager.moveItem(at: oldFolderURL, to: newFolderURL)
            }
            
            var sess = history[index]
            sess["id"] = sanitized
            history[index] = sess
            UserDefaults.standard.set(history, forKey: "sessionHistory")
            loadHistory()
        } catch {
            print("Failed to rename session: \(error.localizedDescription)")
        }
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
    @State private var abuscanJSONURL: URL?
    @State private var colmapImagesURL: URL?
    
    // 3D Historical Map variables
    @State private var historicalPoints: [RawPoint3D] = []
    @State private var historicalTrajectory: [RawPoint3D] = []
    @State private var loading3DData = false
    @State private var rotX: Double = -0.5
    @State private var rotY: Double = 0.5
    @State private var panX: Double = 0.0
    @State private var panY: Double = 0.0
    @State private var panZ: Double = 0.0
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
                ProTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
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
                    .foregroundColor(ProTheme.accentCyan)
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
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private var detailsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Session Details")
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundColor(ProTheme.accentCyan)
                Spacer()
            }
            Divider().background(ProTheme.borderSubtle)
            
            DetailRow(label: "Identifier", value: id)
            DetailRow(label: "Duration", value: String(format: "%.1fs", end.timeIntervalSince(start)))
            DetailRow(label: "Sensor Entries", value: "\(entries) pts")
            DetailRow(label: "GPS Tracking", value: isGPS ? "GPS + IMU Enabled" : "Pure Inertial/Baro Indoor Mode")
        }
        .padding(14)
        .background(ProTheme.cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var syncControlsCard: some View {
        VStack(spacing: 12) {
            Button(action: triggerPhotosSync) {
                HStack {
                    if syncManager.isSyncing {
                        ProgressView()
                            .tint(.black)
                            .padding(.trailing, 8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                    }
                    Text(syncManager.isSyncing ? "SYNCING..." : "SYNC CAMERA IMAGES (SLERP + SLATE)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(syncManager.isSyncing ? ProTheme.accentCyan.opacity(0.4) : ProTheme.accentCyan)
                .foregroundColor(.black)
                .cornerRadius(12)
            }
            .disabled(syncManager.isSyncing)
            
            if !syncManager.syncMessage.isEmpty {
                Text(syncManager.syncMessage)
                    .font(.caption2)
                    .foregroundColor(ProTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var exportLinksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export References & Manifests")
                .font(.caption)
                .fontWeight(.black)
                .foregroundColor(ProTheme.accentCyan)
                .padding(.horizontal)
            
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    // Link 1: Metashape Sync Output
                    if let url = metashapeCSVURL {
                        ShareLink(item: url) {
                            Label("Metashape CSV", systemImage: "arrow.up.doc")
                                .font(.caption)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.18))
                                .foregroundColor(.green)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.45), lineWidth: 1))
                        }
                    }
                    
                    // Link 2: 3D Point Cloud PLY
                    if let url = plyURL {
                        ShareLink(item: url) {
                            Label("PLY Cloud", systemImage: "square.stack.3d.up.fill")
                                .font(.caption)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.purple.opacity(0.18))
                                .foregroundColor(.purple)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.45), lineWidth: 1))
                        }
                    }
                    
                    // Link 3: Raw telemetry logs (60Hz)
                    if let url = csvURL {
                        ShareLink(item: url) {
                            Label("Raw Logs", systemImage: "doc.text")
                                .font(.caption)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.yellow.opacity(0.18))
                                .foregroundColor(.yellow)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.45), lineWidth: 1))
                        }
                    }
                }
                
                if abuscanJSONURL != nil || colmapImagesURL != nil {
                    HStack(spacing: 10) {
                        // Link 4: .abuscan.json Manifest (1-Click Export)
                        if let url = abuscanJSONURL {
                            ShareLink(item: url) {
                                Label(".abuscan.json", systemImage: "curlybraces.square.fill")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(ProTheme.accentCyan.opacity(0.18))
                                    .foregroundColor(ProTheme.accentCyan)
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ProTheme.accentCyan.opacity(0.45), lineWidth: 1))
                            }
                        }
                        
                        // Link 5: COLMAP images.txt (1-Click Export)
                        if let url = colmapImagesURL {
                            ShareLink(item: url) {
                                Label("COLMAP images.txt", systemImage: "camera.metering.matrix")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.orange.opacity(0.18))
                                    .foregroundColor(.orange)
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.45), lineWidth: 1))
                            }
                        }
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
                .foregroundColor(ProTheme.accentCyan)
                .padding(.horizontal)
            
            if syncManager.matchedRecords.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Perform sync to match default library photos")
                            .font(.caption2)
                            .foregroundColor(ProTheme.textSecondary)
                        Spacer()
                    }
                    Spacer()
                }
                .frame(height: 90)
                .background(ProTheme.cardBackground)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ProTheme.borderSubtle, lineWidth: 1))
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
                                        .foregroundColor(ProTheme.textSecondary)
                                }
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(String(format: "Yaw: %.1f°", rec.yaw))
                                        .font(.caption2)
                                        .foregroundColor(ProTheme.accentCyan)
                                    Text(String(format: "Diff: %+.2fs", rec.timeDifferenceSec))
                                        .font(.caption2)
                                        .foregroundColor(abs(rec.timeDifferenceSec) > 0.5 ? .orange : .gray)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ProTheme.cardBackground)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ProTheme.borderSubtle, lineWidth: 1))
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
                .foregroundColor(ProTheme.accentCyan)
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
                .background(ProTheme.cardBackground)
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
                .background(ProTheme.cardBackground)
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
                            rotZ: 0.0,
                            panX: panX,
                            panY: panY,
                            panZ: panZ,
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
                            panZ: $panZ,
                            zoom: $zoom
                        )
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(12)
                    
                    // Interactive Buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            rotX = -0.4
                            rotY = -0.6
                            panX = 0.0
                            panY = 0.0
                            panZ = 0.0
                            zoom = 1.0
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("RESET")
                            }
                            .font(.system(size: 10.5, weight: .black))
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.red.opacity(0.6), lineWidth: 1)
                            )
                        }
                        
                        Button(action: { showTrajectory.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: showTrajectory ? "point.topleft.down.to.point.bottomright.curvepath" : "point.topleft.down.to.point.bottomright.curvepath.fill")
                                Text("PATH")
                            }
                            .font(.system(size: 10.5, weight: .black))
                            .foregroundColor(showTrajectory ? .yellow : .gray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(showTrajectory ? Color.yellow.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        Button(action: { showCamera.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: showCamera ? "camera.fill" : "camera")
                                Text("CAM")
                            }
                            .font(.system(size: 10.5, weight: .black))
                            .foregroundColor(showCamera ? .red : .gray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
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
        
        let fileAbuScan = sessionFolder.appendingPathComponent("\(id).abuscan.json")
        if fileManager.fileExists(atPath: fileAbuScan.path) {
            abuscanJSONURL = fileAbuScan
        }
        
        let fileColmap = sessionFolder.appendingPathComponent("images.txt")
        if fileManager.fileExists(atPath: fileColmap.path) {
            colmapImagesURL = fileColmap
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
