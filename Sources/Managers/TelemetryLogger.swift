import Foundation

struct TelemetryEntry {
    let timestamp: Double // Epoch milliseconds
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
}

class TelemetryLogger {
    private var fileHandle: FileHandle?
    private var csvURL: URL?
    private var currentSessionID: String?
    
    static let shared = TelemetryLogger()
    
    private init() {}
    
    func startNewSession() -> String {
        let sessionID = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
            .prefix(19) // e.g. 2026-05-26_15-30-00
        
        self.currentSessionID = String(sessionID)
        
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return String(sessionID)
        }
        
        let sessionFolderURL = documentsURL.appendingPathComponent("Sessions").appendingPathComponent(String(sessionID))
        try? fileManager.createDirectory(at: sessionFolderURL, withIntermediateDirectories: true, attributes: nil)
        
        let fileURL = sessionFolderURL.appendingPathComponent("telemetry_log.csv")
        self.csvURL = fileURL
        
        // Write CSV Header
        let header = "timestamp_ms,local_x_m,local_y_m,local_z_m,baro_alt_m,baro_press_kpa,pitch_deg,roll_deg,yaw_deg,q_w,q_x,q_y,q_z,gps_enabled,gps_lat,gps_lon,gps_alt_m,gps_acc_h_m,gps_acc_v_m\n"
        
        fileManager.createFile(atPath: fileURL.path, contents: header.data(using: .utf8), attributes: nil)
        
        do {
            self.fileHandle = try FileHandle(forWritingTo: fileURL)
            self.fileHandle?.seekToEndOfFile()
            print("Successfully initialized CSV logger at: \(fileURL.path)")
        } catch {
            print("Failed to initialize CSV FileHandle: \(error.localizedDescription)")
        }
        
        return String(sessionID)
    }
    
    func log(_ entry: TelemetryEntry) {
        guard let fileHandle = fileHandle else { return }
        
        let row = String(
            format: "%.0f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.8f,%.8f,%.8f,%.8f,%d,%.8f,%.8f,%.6f,%.2f,%.2f\n",
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
            entry.verticalAccuracy
        )
        
        if let data = row.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
    
    func stopSession(sparsePointCloud: [RawPoint3D] = []) {
        fileHandle?.closeFile()
        fileHandle = nil
        
        // Save sparse point cloud as a .ply file
        if !sparsePointCloud.isEmpty, let sessionID = currentSessionID {
            savePointCloud(points: sparsePointCloud, sessionID: sessionID)
        }
        
        csvURL = nil
        currentSessionID = nil
    }
    
    private func savePointCloud(points: [RawPoint3D], sessionID: String) {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let plyURL = documentsURL
            .appendingPathComponent("Sessions")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("coverage_cloud.ply")
        
        var plyContent = """
        ply
        format ascii 1.0
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
        print("Saved sparse PLY point cloud (count: \(points.count)) to \(plyURL.path)")
    }
    
    func getCSVPath() -> URL? {
        return csvURL
    }
}
