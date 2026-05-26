import Foundation
import Photos

struct SyncedPhotoRecord: Identifiable {
    let id = UUID()
    let imageName: String
    let timestamp: Double
    let localX: Double
    let localY: Double
    let localZ: Double
    let baroAlt: Double
    let pitch: Double
    let roll: Double
    let yaw: Double
    let latitude: Double
    let longitude: Double
    let gpsAltitude: Double
    let timeDifferenceSec: Double
}

class PhotoSyncManager: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var matchedRecords: [SyncedPhotoRecord] = []
    @Published var syncMessage: String = ""
    
    static let shared = PhotoSyncManager()
    
    private init() {}
    
    func syncPhotos(sessionID: String, startTime: Date, endTime: Date, 
                    leverArmX: Double, leverArmY: Double, leverArmZ: Double,
                    completion: @escaping (Bool, String) -> Void) {
        
        DispatchQueue.main.async {
            self.isSyncing = true
            self.syncMessage = "Requesting Photo Library permissions..."
        }
        
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.isSyncing = false
                    completion(false, "Photo Library access denied.")
                }
                return
            }
            
            self.processSync(sessionID: sessionID, startTime: startTime, endTime: endTime, 
                             lx: leverArmX / 100.0, ly: leverArmY / 100.0, lz: leverArmZ / 100.0, // Convert cm to meters
                             completion: completion)
        }
    }
    
    private func processSync(sessionID: String, startTime: Date, endTime: Date,
                             lx: Double, ly: Double, lz: Double,
                             completion: @escaping (Bool, String) -> Void) {
        
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            DispatchQueue.main.async {
                self.isSyncing = false
                completion(false, "Could not open documents folder.")
            }
            return
        }
        
        let sessionFolderURL = documentsURL.appendingPathComponent("Sessions").appendingPathComponent(sessionID)
        let csvURL = sessionFolderURL.appendingPathComponent("telemetry_log.csv")
        
        guard fileManager.fileExists(atPath: csvURL.path) else {
            DispatchQueue.main.async {
                self.isSyncing = false
                completion(false, "Telemetry log file not found.")
            }
            return
        }
        
        DispatchQueue.main.async {
            self.syncMessage = "Parsing telemetry logs..."
        }
        
        // 1. Parse Telemetry CSV
        guard let csvContent = try? String(contentsOf: csvURL, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.isSyncing = false
                completion(false, "Failed to read CSV log file.")
            }
            return
        }
        
        let telemetryRows = parseCSV(content: csvContent)
        if telemetryRows.isEmpty {
            DispatchQueue.main.async {
                self.isSyncing = false
                completion(false, "No telemetry records found in the log.")
            }
            return
        }
        
        DispatchQueue.main.async {
            self.syncMessage = "Scanning Photo Library for photos taken during session..."
        }
        
        // 2. Query Photo Library
        let fetchOptions = PHFetchOptions()
        // Buffer of 2 seconds before and after to ensure boundary cases are captured
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", 
                                             startTime.addingTimeInterval(-2) as NSDate, 
                                             endTime.addingTimeInterval(2) as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        if fetchResult.count == 0 {
            DispatchQueue.main.async {
                self.isSyncing = false
                completion(false, "No photos found in the Photo Library for this time window.")
            }
            return
        }
        
        DispatchQueue.main.async {
            self.syncMessage = "Matching \(fetchResult.count) photos to spatial coordinates..."
        }
        
        var tempRecords: [SyncedPhotoRecord] = []
        let dispatchGroup = DispatchGroup()
        
        fetchResult.enumerateObjects { (asset, index, stop) in
            dispatchGroup.enter()
            
            let resources = PHAssetResource.assetResources(for: asset)
            let filename = resources.first?.originalFilename ?? "IMG_\(index).HEIC"
            let photoTime = asset.creationDate?.timeIntervalSince1970 ?? 0.0
            let photoTimeMs = photoTime * 1000.0
            
            // Find closest telemetry record
            let closest = self.findClosestTelemetry(timestamp: photoTimeMs, in: telemetryRows)
            let timeDiff = (photoTimeMs - closest.timestamp) / 1000.0 // in seconds
            
            // Rotate the lever arm offset using the logged quaternion (3D orientation)
            let q = (w: closest.q_w, x: closest.q_x, y: closest.q_y, z: closest.q_z)
            let rotatedOffset = self.rotateVector(vector: (lx, ly, lz), q: q)
            
            // Apply translation correction to Local Coordinates
            let correctedX = closest.localX + rotatedOffset.0
            let correctedY = closest.localY + rotatedOffset.1
            let correctedZ = closest.localZ + rotatedOffset.2
            
            // Apply correction to GPS if enabled (Decimal Degrees translation)
            var correctedLat = closest.latitude
            var correctedLon = closest.longitude
            let correctedGpsAlt = closest.gpsAltitude + rotatedOffset.2
            
            if closest.isGPSEnabled && closest.latitude != 0.0 {
                // Approximations in meters to degrees
                let latOffsetDeg = rotatedOffset.1 / 111111.0
                let lonOffsetDeg = rotatedOffset.0 / (111111.0 * cos(closest.latitude * .pi / 180.0))
                
                correctedLat += latOffsetDeg
                correctedLon += lonOffsetDeg
            }
            
            let record = SyncedPhotoRecord(
                imageName: filename,
                timestamp: photoTimeMs,
                localX: correctedX,
                localY: correctedY,
                localZ: correctedZ,
                baroAlt: closest.relativeAltitude + rotatedOffset.2,
                pitch: closest.pitch,
                roll: closest.roll,
                yaw: closest.yaw,
                latitude: correctedLat,
                longitude: correctedLon,
                gpsAltitude: correctedGpsAlt,
                timeDifferenceSec: timeDiff
            )
            
            tempRecords.append(record)
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) {
            // 3. Write final Metashape matched CSV
            let outputCSVURL = sessionFolderURL.appendingPathComponent("metashape_cameras.csv")
            let header = "label,x_local_m,y_local_m,z_local_m,baro_alt_m,latitude,longitude,gps_alt_m,yaw,pitch,roll,time_diff_sec\n"
            
            var body = ""
            for rec in tempRecords {
                body.append(String(
                    format: "%@,%.6f,%.6f,%.6f,%.6f,%.8f,%.8f,%.6f,%.4f,%.4f,%.4f,%.3f\n",
                    rec.imageName,
                    rec.localX,
                    rec.localY,
                    rec.localZ,
                    rec.baroAlt,
                    rec.latitude,
                    rec.longitude,
                    rec.gpsAltitude,
                    rec.yaw,
                    rec.pitch,
                    rec.roll,
                    rec.timeDifferenceSec
                ))
            }
            
            let fullCSV = header + body
            do {
                try fullCSV.write(to: outputCSVURL, atomically: true, encoding: .utf8)
                self.matchedRecords = tempRecords.sorted { $0.imageName < $1.imageName }
                self.isSyncing = false
                completion(true, "Successfully matched \(tempRecords.count) photos! Saved Metashape CSV.")
            } catch {
                self.isSyncing = false
                completion(false, "Failed to write Metashape CSV: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Mathematical & Parsing Helpers
    
    private func parseCSV(content: String) -> [TelemetryEntry] {
        var entries: [TelemetryEntry] = []
        let lines = content.components(separatedBy: .newlines)
        
        // Skip header line
        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: ",")
            if cols.count < 19 { continue }
            
            guard let timestamp = Double(cols[0]),
                  let localX = Double(cols[1]),
                  let localY = Double(cols[2]),
                  let localZ = Double(cols[3]),
                  let baroAlt = Double(cols[4]),
                  let pressure = Double(cols[5]),
                  let pitch = Double(cols[6]),
                  let roll = Double(cols[7]),
                  let yaw = Double(cols[8]),
                  let q_w = Double(cols[9]),
                  let q_x = Double(cols[10]),
                  let q_y = Double(cols[11]),
                  let q_z = Double(cols[12]),
                  let gpsEnabled = Int(cols[13]),
                  let latitude = Double(cols[14]),
                  let longitude = Double(cols[15]),
                  let gpsAlt = Double(cols[16]),
                  let gpsAccH = Double(cols[17]),
                  let gpsAccV = Double(cols[18]) else { continue }
            
            let entry = TelemetryEntry(
                timestamp: timestamp,
                localX: localX,
                localY: localY,
                localZ: localZ,
                relativeAltitude: baroAlt,
                pressure: pressure,
                pitch: pitch,
                roll: roll,
                yaw: yaw,
                q_w: q_w,
                q_x: q_x,
                q_y: q_y,
                q_z: q_z,
                isGPSEnabled: gpsEnabled == 1,
                latitude: latitude,
                longitude: longitude,
                gpsAltitude: gpsAlt,
                horizontalAccuracy: gpsAccH,
                verticalAccuracy: gpsAccV
            )
            entries.append(entry)
        }
        
        return entries
    }
    
    private func findClosestTelemetry(timestamp: Double, in log: [TelemetryEntry]) -> TelemetryEntry {
        // Binary search for efficiency since logs are sorted in time
        var low = 0
        var high = log.count - 1
        
        while low < high {
            let mid = (low + high) / 2
            if log[mid].timestamp < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        // Boundaries checks
        if low == 0 { return log[0] }
        if low >= log.count { return log.last! }
        
        // Find which index is closer
        let diffPrev = abs(log[low - 1].timestamp - timestamp)
        let diffCurr = abs(log[low].timestamp - timestamp)
        
        return diffPrev < diffCurr ? log[low - 1] : log[low]
    }
    
    private func rotateVector(vector: (Double, Double, Double), q: (w: Double, x: Double, y: Double, z: Double)) -> (Double, Double, Double) {
        let (x, y, z) = vector
        
        // 3D vector rotation using unit quaternion
        let num1 = q.x * 2.0
        let num2 = q.y * 2.0
        let num3 = q.z * 2.0
        let num4 = q.x * num1
        let num5 = q.y * num2
        let num6 = q.z * num3
        let num7 = q.x * num2
        let num8 = q.x * num3
        let num9 = q.y * num3
        let num10 = q.w * num1
        let num11 = q.w * num2
        let num12 = q.w * num3
        
        let rx = (1.0 - (num5 + num6)) * x + (num7 - num12) * y + (num8 + num11) * z
        let ry = (num7 + num12) * x + (1.0 - (num4 + num6)) * y + (num9 - num10) * z
        let rz = (num8 - num11) * x + (num9 + num10) * y + (1.0 - (num4 + num5)) * z
        
        return (rx, ry, rz)
    }
}
