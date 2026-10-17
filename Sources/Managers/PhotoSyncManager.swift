import Foundation
import Photos
import ImageIO

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
    var smpteTimecode: String = "00:00:00;00.00"
    var taiNs: UInt64 = 0
}

class PhotoSyncManager: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var matchedRecords: [SyncedPhotoRecord] = []
    @Published var syncMessage: String = ""
    
    static let shared = PhotoSyncManager()
    
    private init() {}
    
    func syncPhotos(sessionID: String, startTime: Date, endTime: Date, 
                    leverArmX: Double, leverArmY: Double, leverArmZ: Double,
                    slateOffsetMs: Double = AbuClockKitBridge.shared.manualSlateOffsetMs,
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
                             slateOffsetMs: slateOffsetMs,
                             completion: completion)
        }
    }
    
    private func processSync(sessionID: String, startTime: Date, endTime: Date,
                             lx: Double, ly: Double, lz: Double,
                             slateOffsetMs: Double,
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
            self.syncMessage = "Parsing AbuClock telemetry logs..."
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
            self.syncMessage = "Scanning Photo Library for DSLR/iOS photos taken during session..."
        }
        
        // 2. Query Photo Library
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", 
                                             startTime.addingTimeInterval(-5) as NSDate, 
                                             endTime.addingTimeInterval(5) as NSDate)
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
            self.syncMessage = "Interpolating \(fetchResult.count) photos via sub-ms SLERP + AbuClock..."
        }
        
        var tempRecords: [SyncedPhotoRecord] = []
        var manifestEntries: [AbuScanCaptureManifestEntry] = []
        let recordsLock = NSLock()
        let dispatchGroup = DispatchGroup()
        let imageManager = PHImageManager.default()
        let reqOptions = PHImageRequestOptions()
        reqOptions.isSynchronous = false
        reqOptions.deliveryMode = .fastFormat
        reqOptions.isNetworkAccessAllowed = false
        
        fetchResult.enumerateObjects { (asset, index, _) in
            dispatchGroup.enter()
            
            let resources = PHAssetResource.assetResources(for: asset)
            let filename = resources.first?.originalFilename ?? "IMG_\(index).HEIC"
            let basePhotoTimeSec = asset.creationDate?.timeIntervalSince1970 ?? 0.0
            
            imageManager.requestImageDataAndOrientation(for: asset, options: reqOptions) { data, _, _, _ in
                // Extract sub-second EXIF (SubSecTimeOriginal + ExposureTime/2) if available
                var exactPhotoTimeMs = basePhotoTimeSec * 1000.0
                if let imgData = data,
                   let source = CGImageSourceCreateWithData(imgData as CFData, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                   let exif = props[String(kCGImagePropertyExifDictionary)] as? [String: Any] {
                    
                    var subSecMs: Double = 0.0
                    if let subSecStr = exif[String(kCGImagePropertyExifSubsecTimeOriginal)] as? String,
                       let frac = Double("0." + subSecStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        subSecMs = frac * 1000.0
                    }
                    var halfExpMs: Double = 4.0
                    if let expSec = exif[String(kCGImagePropertyExifExposureTime)] as? Double, expSec > 0 {
                        halfExpMs = (expSec * 0.5) * 1000.0
                    }
                    // If creationDate had whole-second resolution, add SubSecTimeOriginal
                    let fractionalCheck = (basePhotoTimeSec * 1000.0).truncatingRemainder(dividingBy: 1000.0)
                    if fractionalCheck < 1.0 && subSecMs > 0.0 {
                        exactPhotoTimeMs = floor(basePhotoTimeSec) * 1000.0 + subSecMs + halfExpMs
                    } else {
                        exactPhotoTimeMs = basePhotoTimeSec * 1000.0 + halfExpMs
                    }
                }
                
                // Apply calibrated Frame-00 Optical Slate Offset (in milliseconds)
                let calibratedPhotoTimeMs = exactPhotoTimeMs + slateOffsetMs
                
                // Perform sub-millisecond Linear + Quaternion SLERP interpolation between bracketing 60Hz entries
                let (interp, timeDiffSec) = self.interpolateTelemetry(timestampMs: calibratedPhotoTimeMs, in: telemetryRows)
                
                if abs(timeDiffSec) <= 10.0 {
                    let q = (w: interp.q_w, x: interp.q_x, y: interp.q_y, z: interp.q_z)
                    let rotatedOffset = self.rotateVector(vector: (lx, ly, lz), q: q)
                    
                    let correctedX = interp.localX - rotatedOffset.0
                    let correctedY = interp.localY - rotatedOffset.1
                    let correctedZ = interp.localZ - rotatedOffset.2
                    
                    var correctedLat = interp.latitude
                    var correctedLon = interp.longitude
                    let correctedGpsAlt = interp.gpsAltitude - rotatedOffset.2
                    
                    if interp.isGPSEnabled && interp.latitude != 0.0 {
                        let latOffsetDeg = rotatedOffset.1 / 111111.0
                        let lonOffsetDeg = rotatedOffset.0 / (111111.0 * cos(interp.latitude * .pi / 180.0))
                        correctedLat -= latOffsetDeg
                        correctedLon -= lonOffsetDeg
                    }
                    
                    let taiNs = UInt64(max((calibratedPhotoTimeMs * 0.001 + AbuClockKitBridge.taiMinusUtcSeconds), 0.0) * 1_000_000_000.0)
                    let stamp = AbuClockKitBridge.shared.stampAtTaiNanoseconds(taiNs: taiNs, fileExtension: "dng")
                    
                    let record = SyncedPhotoRecord(
                        imageName: filename,
                        timestamp: calibratedPhotoTimeMs,
                        localX: correctedX,
                        localY: correctedY,
                        localZ: correctedZ,
                        baroAlt: interp.relativeAltitude - rotatedOffset.2,
                        pitch: interp.pitch,
                        roll: interp.roll,
                        yaw: interp.yaw,
                        latitude: correctedLat,
                        longitude: correctedLon,
                        gpsAltitude: correctedGpsAlt,
                        timeDifferenceSec: timeDiffSec,
                        smpteTimecode: stamp.smpteWithSubframe,
                        taiNs: stamp.disciplinedTaiNanoseconds
                    )
                    
                    let manifestEntry = AbuScanCaptureManifestEntry(
                        image_id: index + 1,
                        sensor_id: "ExternalDSLR_Synced",
                        file_path: filename,
                        lidar_ply_path: nil,
                        smpte_timecode: stamp.smpteWithSubframe,
                        bcd_timecode: stamp.bcdTimecode,
                        tai_ns: stamp.disciplinedTaiNanoseconds,
                        subframe_phase: stamp.subframePhase,
                        error_ns: Int64(timeDiffSec * 1_000_000_000.0),
                        qw: interp.q_w,
                        qx: interp.q_x,
                        qy: interp.q_y,
                        qz: interp.q_z,
                        tx_m: correctedX,
                        ty_m: correctedY,
                        tz_m: correctedZ,
                        camera_model_id: 1
                    )
                    
                    recordsLock.lock()
                    tempRecords.append(record)
                    manifestEntries.append(manifestEntry)
                    recordsLock.unlock()
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            // 3. Write final Metashape matched CSV (with AbuClock SMPTE & TAI columns)
            let outputCSVURL = sessionFolderURL.appendingPathComponent("metashape_cameras.csv")
            let header = "label,x_local_m,y_local_m,z_local_m,baro_alt_m,latitude,longitude,gps_alt_m,yaw,pitch,roll,time_diff_sec,smpte_timecode,tai_ns\n"
            
            let sortedRecords = tempRecords.sorted { $0.imageName < $1.imageName }
            var body = ""
            for rec in sortedRecords {
                body.append(String(
                    format: "%@,%.6f,%.6f,%.6f,%.6f,%.8f,%.8f,%.6f,%.4f,%.4f,%.4f,%.4f,%@,%llu\n",
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
                    rec.timeDifferenceSec,
                    rec.smpteTimecode,
                    rec.taiNs
                ))
            }
            
            let fullCSV = header + body
            do {
                try fullCSV.write(to: outputCSVURL, atomically: true, encoding: .utf8)
                self.matchedRecords = sortedRecords
                self.isSyncing = false
                completion(true, "Synced \(sortedRecords.count) photos via sub-ms AbuClock SLERP! Saved Metashape CSV.")
            } catch {
                self.isSyncing = false
                completion(false, "Failed to write Metashape CSV: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Mathematical, SLERP & Parsing Helpers
    
    private func parseCSV(content: String) -> [TelemetryEntry] {
        var entries: [TelemetryEntry] = []
        let lines = content.components(separatedBy: .newlines)
        
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
            
            var taiNs: UInt64 = 0
            var smpte = "00:00:00;00.00"
            var bcd: UInt32 = 0
            var phase: Double = 0.0
            var lockStr = "Locked"
            if cols.count >= 24 {
                taiNs = UInt64(cols[19]) ?? 0
                smpte = cols[20]
                bcd = UInt32(cols[21]) ?? 0
                phase = Double(cols[22]) ?? 0.0
                lockStr = cols[23]
            }
            
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
                verticalAccuracy: gpsAccV,
                taiNs: taiNs,
                smpteTimecode: smpte,
                bcdTimecode: bcd,
                subframePhase: phase,
                clockLockState: lockStr
            )
            entries.append(entry)
        }
        
        return entries
    }
    
    /// Performs sub-millisecond Linear Translation + Quaternion SLERP interpolation between
    /// the two bracketing 60Hz telemetry samples (t0 <= timestampMs <= t1).
    private func interpolateTelemetry(timestampMs: Double, in log: [TelemetryEntry]) -> (TelemetryEntry, Double) {
        if log.count == 1 {
            return (log[0], (timestampMs - log[0].timestamp) / 1000.0)
        }
        
        var low = 0
        var high = log.count - 1
        while low < high {
            let mid = (low + high) / 2
            if log[mid].timestamp < timestampMs {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        if low == 0 {
            return (log[0], (timestampMs - log[0].timestamp) / 1000.0)
        }
        if low >= log.count {
            let last = log.last!
            return (last, (timestampMs - last.timestamp) / 1000.0)
        }
        
        let e0 = log[low - 1]
        let e1 = log[low]
        let dt = e1.timestamp - e0.timestamp
        if dt <= 0.0001 {
            return (e0, (timestampMs - e0.timestamp) / 1000.0)
        }
        
        let alpha = max(0.0, min(1.0, (timestampMs - e0.timestamp) / dt))
        let slerpQ = slerpQuaternion(
            q0: (e0.q_w, e0.q_x, e0.q_y, e0.q_z),
            q1: (e1.q_w, e1.q_x, e1.q_y, e1.q_z),
            t: alpha
        )
        
        let interp = TelemetryEntry(
            timestamp: timestampMs,
            localX: e0.localX + (e1.localX - e0.localX) * alpha,
            localY: e0.localY + (e1.localY - e0.localY) * alpha,
            localZ: e0.localZ + (e1.localZ - e0.localZ) * alpha,
            relativeAltitude: e0.relativeAltitude + (e1.relativeAltitude - e0.relativeAltitude) * alpha,
            pressure: e0.pressure + (e1.pressure - e0.pressure) * alpha,
            pitch: e0.pitch + (e1.pitch - e0.pitch) * alpha,
            roll: e0.roll + (e1.roll - e0.roll) * alpha,
            yaw: interpolateAngleDeg(a0: e0.yaw, a1: e1.yaw, t: alpha),
            q_w: slerpQ.0,
            q_x: slerpQ.1,
            q_y: slerpQ.2,
            q_z: slerpQ.3,
            isGPSEnabled: e0.isGPSEnabled,
            latitude: e0.latitude + (e1.latitude - e0.latitude) * alpha,
            longitude: e0.longitude + (e1.longitude - e0.longitude) * alpha,
            gpsAltitude: e0.gpsAltitude + (e1.gpsAltitude - e0.gpsAltitude) * alpha,
            horizontalAccuracy: e0.horizontalAccuracy,
            verticalAccuracy: e0.verticalAccuracy,
            taiNs: e0.taiNs,
            smpteTimecode: e0.smpteTimecode,
            bcdTimecode: e0.bcdTimecode,
            subframePhase: e0.subframePhase,
            clockLockState: e0.clockLockState
        )
        let nearestDiffSec = min(abs(timestampMs - e0.timestamp), abs(e1.timestamp - timestampMs)) / 1000.0
        return (interp, nearestDiffSec)
    }
    
    private func interpolateAngleDeg(a0: Double, a1: Double, t: Double) -> Double {
        var diff = a1 - a0
        while diff > 180.0 { diff -= 360.0 }
        while diff < -180.0 { diff += 360.0 }
        var res = a0 + diff * t
        if res > 180.0 { res -= 360.0 }
        if res < -180.0 { res += 360.0 }
        return res
    }
    
    private func slerpQuaternion(
        q0: (Double, Double, Double, Double),
        q1: (Double, Double, Double, Double),
        t: Double
    ) -> (Double, Double, Double, Double) {
        var (w1, x1, y1, z1) = q1
        var dot = q0.0 * w1 + q0.1 * x1 + q0.2 * y1 + q0.3 * z1
        if dot < 0.0 {
            dot = -dot
            w1 = -w1; x1 = -x1; y1 = -y1; z1 = -z1
        }
        if dot > 0.9995 {
            let rw = q0.0 + t * (w1 - q0.0)
            let rx = q0.1 + t * (x1 - q0.1)
            let ry = q0.2 + t * (y1 - q0.2)
            let rz = q0.3 + t * (z1 - q0.3)
            let norm = max(sqrt(rw*rw + rx*rx + ry*ry + rz*rz), 1e-12)
            return (rw / norm, rx / norm, ry / norm, rz / norm)
        }
        let theta0 = acos(max(-1.0, min(1.0, dot)))
        let theta = theta0 * t
        let sinTheta = sin(theta)
        let sinTheta0 = max(sin(theta0), 1e-12)
        let s0 = cos(theta) - dot * sinTheta / sinTheta0
        let s1 = sinTheta / sinTheta0
        return (
            s0 * q0.0 + s1 * w1,
            s0 * q0.1 + s1 * x1,
            s0 * q0.2 + s1 * y1,
            s0 * q0.3 + s1 * z1
        )
    }
    
    private func rotateVector(vector: (Double, Double, Double), q: (w: Double, x: Double, y: Double, z: Double)) -> (Double, Double, Double) {
        let (x, y, z) = vector
        
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
