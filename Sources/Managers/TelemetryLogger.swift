import Foundation

struct TelemetryEntry {
    let timestamp: Double // Epoch milliseconds (Kalman PLL disciplined)
    let localX: Double
    let localY: Double
    let localZ: Double
    let relativeAltitude: Double
    let pressure: Double
    let pitch: Double
    let roll: Double
    let yaw: Double
    let q_w: Double
    let q_x: Double
    let q_y: Double
    let q_z: Double
    let isGPSEnabled: Bool
    let latitude: Double
    let longitude: Double
    let gpsAltitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    // Abu Clock SMPTE ST 12-1 / ST 2059-2 & TAI Timestep fields
    var taiNs: UInt64 = 0
    var smpteTimecode: String = "00:00:00;00.00"
    var bcdTimecode: UInt32 = 0
    var subframePhase: Double = 0.0
    var clockLockState: String = "Locked"
}

/// Synchronized multi-sensor capture entry for `.abuscan.json` and COLMAP `images.txt`.
struct AbuScanCaptureManifestEntry: Codable {
    let image_id: Int
    let sensor_id: String
    let file_path: String
    let lidar_ply_path: String?
    let smpte_timecode: String
    let bcd_timecode: UInt32
    let tai_ns: UInt64
    let subframe_phase: Double
    let error_ns: Int64
    let qw: Double
    let qx: Double
    let qy: Double
    let qz: Double
    let tx_m: Double
    let ty_m: Double
    let tz_m: Double
    let camera_model_id: Int
}

class TelemetryLogger {
    private var fileHandle: FileHandle?
    private var csvURL: URL?
    private var currentSessionID: String?
    private var captureManifestEntries: [AbuScanCaptureManifestEntry] = []
    private let logLock = NSLock()
    
    static let shared = TelemetryLogger()
    
    private init() {}
    
    func startNewSession() -> String {
        logLock.lock()
        defer { logLock.unlock() }
        
        let sessionID = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
            .prefix(19) // e.g. 2026-05-26_15-30-00
        
        self.currentSessionID = String(sessionID)
        self.captureManifestEntries.removeAll()
        
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return String(sessionID)
        }
        
        let sessionFolderURL = documentsURL.appendingPathComponent("Sessions").appendingPathComponent(String(sessionID))
        try? fileManager.createDirectory(at: sessionFolderURL, withIntermediateDirectories: true, attributes: nil)
        
        let fileURL = sessionFolderURL.appendingPathComponent("telemetry_log.csv")
        self.csvURL = fileURL
        
        // Write CSV Header (First 19 columns preserved for backward compatibility + 5 Abu Clock columns)
        let header = "timestamp_ms,local_x_m,local_y_m,local_z_m,baro_alt_m,baro_press_kpa,pitch_deg,roll_deg,yaw_deg,q_w,q_x,q_y,q_z,gps_enabled,gps_lat,gps_lon,gps_alt_m,gps_acc_h_m,gps_acc_v_m,tai_ns,smpte_timecode,bcd_timecode,subframe_phase,clock_lock_state\n"
        
        fileManager.createFile(atPath: fileURL.path, contents: header.data(using: .utf8), attributes: nil)
        
        do {
            self.fileHandle = try FileHandle(forWritingTo: fileURL)
            self.fileHandle?.seekToEndOfFile()
            print("Successfully initialized AbuClock-enriched CSV logger at: \(fileURL.path)")
        } catch {
            print("Failed to initialize CSV FileHandle: \(error.localizedDescription)")
        }
        
        return String(sessionID)
    }
    
    func log(_ entry: TelemetryEntry) {
        logLock.lock()
        defer { logLock.unlock() }
        guard let fileHandle = fileHandle else { return }
        
        let row = String(
            format: "%.3f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.8f,%.8f,%.8f,%.8f,%d,%.8f,%.8f,%.6f,%.2f,%.2f,%llu,%@,%u,%.6f,%@\n",
            entry.timestamp,
            entry.localX,
            entry.localY,
            entry.localZ,
            entry.relativeAltitude,
            entry.pressure,
            entry.pitch,
            entry.roll,
            entry.yaw,
            entry.q_w,
            entry.q_x,
            entry.q_y,
            entry.q_z,
            entry.isGPSEnabled ? 1 : 0,
            entry.latitude,
            entry.longitude,
            entry.gpsAltitude,
            entry.horizontalAccuracy,
            entry.verticalAccuracy,
            entry.taiNs,
            entry.smpteTimecode,
            entry.bcdTimecode,
            entry.subframePhase,
            entry.clockLockState.replacingOccurrences(of: ",", with: ";")
        )
        
        if let data = row.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
    
    /// Records a synchronized photo + LiDAR snapshot at the exact `OpticalMidpointStamp`
    /// and updates the session's `.abuscan.json` and COLMAP `images.txt` manifests.
    func recordSynchronizedCapture(
        stamp: OpticalMidpointStamp,
        photoFilename: String,
        lidarSnapshotPoints: [RawPoint3D],
        qw: Double, qx: Double, qy: Double, qz: Double,
        tx: Double, ty: Double, tz: Double
    ) {
        logLock.lock()
        guard let sessionID = currentSessionID else {
            logLock.unlock()
            return
        }
        let nextId = captureManifestEntries.count + 1
        var lidarPlyName: String? = nil
        if !lidarSnapshotPoints.isEmpty {
            let token = stamp.smpteTimecode.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: ";", with: "")
            let plyName = "\(stamp.sensorId)_LiDAR_\(token)_\(stamp.disciplinedTaiNanoseconds).ply"
            lidarPlyName = plyName
            savePointCloud(points: lidarSnapshotPoints, sessionID: sessionID, customFilename: plyName)
        }
        
        let manifestEntry = AbuScanCaptureManifestEntry(
            image_id: nextId,
            sensor_id: stamp.sensorId,
            file_path: photoFilename,
            lidar_ply_path: lidarPlyName,
            smpte_timecode: stamp.smpteWithSubframe,
            bcd_timecode: stamp.bcdTimecode,
            tai_ns: stamp.disciplinedTaiNanoseconds,
            subframe_phase: stamp.subframePhase,
            error_ns: AbuClockKitBridge.shared.offsetNanoseconds,
            qw: qw,
            qx: qx,
            qy: qy,
            qz: qz,
            tx_m: tx,
            ty_m: ty,
            tz_m: tz,
            camera_model_id: 1
        )
        captureManifestEntries.append(manifestEntry)
        let currentEntries = captureManifestEntries
        logLock.unlock()
        
        exportAbuScanAndColmapManifests(sessionID: sessionID, entries: currentEntries)
    }
    
    func stopSession(sparsePointCloud: [RawPoint3D] = []) {
        logLock.lock()
        fileHandle?.closeFile()
        fileHandle = nil
        let sessionID = currentSessionID
        let entries = captureManifestEntries
        csvURL = nil
        currentSessionID = nil
        logLock.unlock()
        
        if let sid = sessionID {
            if !sparsePointCloud.isEmpty {
                savePointCloud(points: sparsePointCloud, sessionID: sid, customFilename: "coverage_cloud.ply")
            }
            if !entries.isEmpty {
                exportAbuScanAndColmapManifests(sessionID: sid, entries: entries)
            }
        }
    }
    
    private func savePointCloud(points: [RawPoint3D], sessionID: String, customFilename: String = "coverage_cloud.ply") {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let plyURL = documentsURL
            .appendingPathComponent("Sessions")
            .appendingPathComponent(sessionID)
            .appendingPathComponent(customFilename)
        
        var plyContent = """
        ply
        format ascii 1.0
        comment AbuClock Synchronized Point Cloud (Session: \(sessionID))
        element vertex \(points.count)
        property float x
        property float y
        property float z
        end_header
        """
        
        for pt in points {
            plyContent.append(String(format: "\n%.4f %.4f %.4f", pt.x, pt.y, pt.z))
        }
        
        try? plyContent.write(to: plyURL, atomically: true, encoding: .utf8)
        print("Saved PLY point cloud (\(customFilename), count: \(points.count)) to \(plyURL.path)")
    }
    
    private func exportAbuScanAndColmapManifests(sessionID: String, entries: [AbuScanCaptureManifestEntry]) {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let sessionFolderURL = documentsURL.appendingPathComponent("Sessions").appendingPathComponent(sessionID)
        
        // 1. Export .abuscan.json (abuscan.manifest.v1)
        let abuscanURL = sessionFolderURL.appendingPathComponent("\(sessionID).abuscan.json")
        let bridge = AbuClockKitBridge.shared
        let rootObj: [String: Any] = [
            "schema": "abuscan.manifest.v1",
            "session_name": sessionID,
            "fps_num": bridge.fpsNum,
            "fps_den": bridge.fpsDen,
            "drop_frame": bridge.dropFrame,
            "clock_lock_state": bridge.lockState,
            "captures": entries.map { e in
                [
                    "image_id": e.image_id,
                    "sensor_id": e.sensor_id,
                    "file_path": e.file_path,
                    "lidar_ply_path": e.lidar_ply_path ?? "",
                    "smpte_timecode": e.smpte_timecode,
                    "bcd_timecode": e.bcd_timecode,
                    "tai_ns": e.tai_ns,
                    "subframe_phase": e.subframe_phase,
                    "error_ns": e.error_ns,
                    "qw": e.qw,
                    "qx": e.qx,
                    "qy": e.qy,
                    "qz": e.qz,
                    "tx_m": e.tx_m,
                    "ty_m": e.ty_m,
                    "tz_m": e.tz_m,
                    "camera_model_id": e.camera_model_id
                ] as [String: Any]
            }
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: rootObj, options: [.prettyPrinted, .sortedKeys]) {
            try? jsonData.write(to: abuscanURL, options: .atomic)
        }
        
        // 2. Export COLMAP images.txt
        let colmapURL = sessionFolderURL.appendingPathComponent("images.txt")
        var colmapTxt = "# Image list with two lines of data per image:\n"
        colmapTxt += "#   IMAGE_ID, QW, QX, QY, QZ, TX, TY, TZ, CAMERA_ID, NAME\n"
        colmapTxt += "#   POINTS2D[] as (X, Y, POINT3D_ID)\n"
        for e in entries {
            colmapTxt += String(
                format: "%d %.6f %.6f %.6f %.6f %.6f %.6f %.6f %d %@\n\n",
                e.image_id, e.qw, e.qx, e.qy, e.qz, e.tx_m, e.ty_m, e.tz_m, e.camera_model_id, e.file_path
            )
        }
        try? colmapTxt.write(to: colmapURL, atomically: true, encoding: .utf8)
    }
    
    func getCSVPath() -> URL? {
        return csvURL
    }
}
