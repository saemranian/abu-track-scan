import Foundation
import AVFoundation
import CoreMedia
import Combine
#if canImport(Darwin)
import Darwin
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Optical Exposure Midpoint Timecode & Pose Stamp produced by `AbuClockKit` for
/// the Abu Track & Scan iOS Application.
///
/// Compensates for CMOS rolling-shutter readout duration (`8 ms` to `16 ms` top-to-bottom scan)
/// by reading `CMSampleBufferGetOutputPresentationTimeStamp()` from `AVFoundation` and
/// `ARFrame.timestamp` from `ARKit`, translating that Mach kernel timestamp directly through
/// AbuClock's 2-state Kalman PLL disciplined `OverlayClock`.
public struct OpticalMidpointStamp: Sendable, Codable {
    public let sensorId: String
    public let hostMachNanoseconds: UInt64
    public let disciplinedTaiNanoseconds: UInt64
    public let smpteTimecode: String
    public let smpteWithSubframe: String
    public let bcdTimecode: UInt32
    public let subframePhase: Double
    public let frameIndex: UInt64
    public let fpsNum: UInt32
    public let fpsDen: UInt32
    public let dropFrame: Bool
    public let clockLockState: String
    public let captureFilename: String
}

/// 6DoF camera tracking pose from ARKit (`ARFrame.camera.transform`) paired with optical lens data.
public struct AbuTrackPose6DoF: Sendable, Codable {
    public let cameraId: UInt8
    public let panDeg: Double
    public let tiltDeg: Double
    public let rollDeg: Double
    public let xMm: Double
    public let yMm: Double
    public let zMm: Double
    public let zoomRaw: UInt32
    public let focusRaw: UInt32

    public init(
        cameraId: UInt8 = 1,
        panDeg: Double = 0.0,
        tiltDeg: Double = 0.0,
        rollDeg: Double = 0.0,
        xMm: Double = 0.0,
        yMm: Double = 0.0,
        zMm: Double = 0.0,
        zoomRaw: UInt32 = 1024,
        focusRaw: UInt32 = 2048
    ) {
        self.cameraId = cameraId
        self.panDeg = panDeg
        self.tiltDeg = tiltDeg
        self.rollDeg = rollDeg
        self.xMm = xMm
        self.yMm = yMm
        self.zMm = zMm
        self.zoomRaw = zoomRaw
        self.focusRaw = focusRaw
    }
}

/// Discovery Beacon returned by Abu Clock Master on UDP 50320 (`ABU_ECO_V1`) or HTTP `:7878/api/ecosystem/discover`.
public struct AbuClockDiscoveryBeacon: Codable {
    public let magic: String?
    public let version: String?
    public let master_ip: String
    public let csptp_event_port: Int?
    public let sntp_general_port: Int?
    public let http_api_port: Int?
    public let abutrack_telemetry_port: Int?
    public let abutrack_video_port: Int?
    public let ptp_domain: Int?
    public let fps_num: UInt32?
    public let fps_den: UInt32?
    public let drop_frame: Bool?
    public let tai_ns: UInt64?
    public let smpte_timecode: String?
    public let bcd_hex: String?
    public let trigger_lead_time_ms: Int?
}

/// Future-Time Multi-Sensor Capture Barrier (`SCHEDULE_CAPTURE_AT` on UDP 50319).
public struct AbuClockCaptureBarrier: Codable {
    public let command: String
    public let sequence_id: UInt64
    public let target_tai_ns: UInt64
    public let smpte_timecode: String?
    public let bcd_hex: String?
    public let lead_time_ms: UInt64?
    public let format: String?
}

/// Receipt returned to Abu Clock Master after executing a `SCHEDULE_CAPTURE_AT` barrier.
public struct AbuClockCaptureReceipt: Codable {
    public let sequence_id: UInt64
    public let sensor_id: String
    public let platform: String
    public let target_tai_ns: UInt64
    public let actual_tai_ns: UInt64
    public let jitter_ns: Int64
    public let filename: String
    public let within_subframe_budget: Bool
}

/// Embedded Abu Clock Timing, 2-State Kalman PLL, Auto-Discovery (`UDP 50320`),
/// and Future-Time Capture Barrier (`UDP 50319`) Engine for iOS (`Abu Track & Scan`).
public final class AbuClockKitBridge: ObservableObject {
    public static let shared = AbuClockKitBridge()

    // Current TAI - UTC leap second offset (37 seconds per IERS Bulletin C)
    public static let taiMinusUtcSeconds: Double = 37.0

    // Published UI & Telemetry state
    @Published public var sensorId: String = "iPhone16Pro_CamA"
    @Published public var fpsNum: UInt32 = 30000
    @Published public var fpsDen: UInt32 = 1001
    @Published public var dropFrame: Bool = true
    @Published public var ptpDomain: Int = 1

    @Published public var lockState: String = "Locked (Field Master)"
    @Published public var discoveredMasterIP: String = ""
    @Published public var offsetNanoseconds: Int64 = 0
    @Published public var driftPpb: Double = 0.0
    @Published public var rttMicroseconds: Double = 0.0
    @Published public var liveSmpteTimecode: String = "00:00:00;00.00"
    @Published public var liveBcdHex: String = "0x00000000"
    @Published public var liveSubframePhase: Double = 0.0
    @Published public var liveTaiNanoseconds: UInt64 = 0
    @Published public var isFlashMarkerFrameZero: Bool = false
    @Published public var lastBarrierReceiptSummary: String = "Ready (UDP 50319)"

    // Slate metadata for Full-Screen Digital Clapper Slate
    @Published public var slateProductionName: String = "ABU STUDIO VP"
    @Published public var slateScene: String = "SC_01"
    @Published public var slateTake: Int = 1
    @Published public var slateCameraRoll: String = "A001"
    @Published public var manualSlateOffsetMs: Double = 0.0

    // Callback invoked at the exact nanosecond of a SCHEDULE_CAPTURE_AT barrier
    public var onScheduledCaptureTrigger: ((AbuClockCaptureBarrier, OpticalMidpointStamp) -> Void)?

    // Internal 2-State Kalman Filter PLL state protected by lock
    private let stateLock = NSLock()
    private var anchorTaiNs: UInt64
    private var anchorMonoNs: UInt64
    private var kalmanOffsetNs: Double = 0.0
    private var kalmanDriftPpb: Double = 0.0
    private var p00: Double = 1.0e12
    private var p01: Double = 0.0
    private var p10: Double = 0.0
    private var p11: Double = 1.0e6
    private var lastSyncMonoNs: UInt64 = 0
    private var syncSampleCount: Int = 0

    // Background timers and UDP listener
    private var syncTimer: DispatchSourceTimer?
    private var barrierListenerActive: Bool = false
    private var barrierSocketFD: Int32 = -1
    private let clockQueue = DispatchQueue(label: "com.abutrack.abuclock.pll", qos: .userInteractive)
    private let barrierQueue = DispatchQueue(label: "com.abutrack.abuclock.barrier", qos: .userInteractive)

    public init(
        sensorId: String = "iPhone16Pro_CamA",
        fpsNum: UInt32 = 30000,
        fpsDen: UInt32 = 1001,
        dropFrame: Bool = true
    ) {
        self.sensorId = sensorId
        self.fpsNum = fpsNum
        self.fpsDen = max(fpsDen, 1)
        self.dropFrame = dropFrame

        let nowUtcSec = Date().timeIntervalSince1970
        let nowTaiSec = nowUtcSec + Self.taiMinusUtcSeconds
        self.anchorTaiNs = UInt64(max(nowTaiSec, 0.0) * 1_000_000_000.0)
        self.anchorMonoNs = Self.currentMachNanoseconds()
        self.lastSyncMonoNs = self.anchorMonoNs

        startBarrierListenerOnPort50319()
        startContinuousKalmanSyncLoop()
    }

    // MARK: - Monotonic Hardware Clock (`mach_continuous_time`)

    /// Reads the host Apple Silicon `mach_continuous_time()` scaled to nanoseconds.
    public static func currentMachNanoseconds() -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let ticks = mach_continuous_time()
        let denom = UInt64(max(info.denom, 1))
        return (ticks &* UInt64(info.numer)) / denom
    }

    /// Returns the current disciplined TAI timestamp in nanoseconds.
    public func nowTaiNanoseconds() -> UInt64 {
        let monoNow = Self.currentMachNanoseconds()
        return translateMachToTaiNanoseconds(monoNow)
    }

    /// Translates any Mach monotonic nanosecond timestamp into disciplined TAI nanoseconds
    /// via the 2-state Kalman PLL equation:
    ///   T_TAI(t) = T_TAI,0 + (t - t_0) * (1 + alpha_freq * 1e-9) + theta_0
    public func translateMachToTaiNanoseconds(_ hostMonoNs: UInt64) -> UInt64 {
        stateLock.lock()
        let baseTai = anchorTaiNs
        let baseMono = anchorMonoNs
        let offsetNs = kalmanOffsetNs
        let drift = kalmanDriftPpb
        stateLock.unlock()

        let deltaNs = Double(Int64(bitPattern: hostMonoNs &- baseMono))
        let driftCorrection = deltaNs * (drift * 1.0e-9)
        let totalCorrection = Int64(deltaNs + driftCorrection + offsetNs)
        let signedResult = Int64(bitPattern: baseTai) &+ totalCorrection
        return UInt64(max(signedResult, 0))
    }

    // MARK: - Exposure Midpoint & SMPTE ST 12-1 / ST 2059-2 Timecode Synthesis

    /// Translates an `AVFoundation` `CMSampleBuffer` optical exposure midpoint timestamp
    /// (`T_mid = T_SOF + T_exposure / 2`) into disciplined TAI nanoseconds and SMPTE timecode.
    public func stampVideoSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        exposureDurationSeconds: Double = 0.008,
        fileExtension: String = "heic"
    ) -> OpticalMidpointStamp {
        let pts = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
        let ptsSeconds = CMTimeGetSeconds(pts)
        let midpointSeconds = ptsSeconds + (exposureDurationSeconds * 0.5)
        let hostMonoNs = UInt64(max(midpointSeconds, 0.0) * 1_000_000_000.0)
        return stampMonotonicNanoseconds(hostMonoNs, fileExtension: fileExtension)
    }

    /// Translates an `ARKit` `ARFrame.timestamp` (Mach uptime seconds at optical exposure midpoint)
    /// into disciplined TAI nanoseconds and SMPTE ST 12-1 timecode.
    public func stampArKitTimestamp(
        arFrameTimestampSeconds: TimeInterval,
        fileExtension: String = "dng"
    ) -> OpticalMidpointStamp {
        let hostMonoNs = UInt64(max(arFrameTimestampSeconds, 0.0) * 1_000_000_000.0)
        return stampMonotonicNanoseconds(hostMonoNs, fileExtension: fileExtension)
    }

    /// Synthesizes a complete `OpticalMidpointStamp` for any monotonic Mach nanosecond reading.
    public func stampMonotonicNanoseconds(
        _ hostMonoNs: UInt64,
        sensorOverride: String? = nil,
        fileExtension: String = "dng"
    ) -> OpticalMidpointStamp {
        let taiNs = translateMachToTaiNanoseconds(hostMonoNs)
        return stampAtTaiNanoseconds(
            taiNs: taiNs,
            hostMonoNs: hostMonoNs,
            sensorOverride: sensorOverride,
            fileExtension: fileExtension
        )
    }

    /// Synthesizes SMPTE ST 12-1 / ST 2059-2 timecode, 32-bit BCD word, and sub-frame phase at `taiNs`.
    public func stampAtTaiNanoseconds(
        taiNs: UInt64,
        hostMonoNs: UInt64 = 0,
        sensorOverride: String? = nil,
        fileExtension: String = "dng"
    ) -> OpticalMidpointStamp {
        stateLock.lock()
        let activeSensor = sensorOverride ?? sensorId
        let num = max(fpsNum, 1)
        let den = max(fpsDen, 1)
        let isDF = dropFrame
        let currentLock = lockState
        stateLock.unlock()

        // Nominal integer fps (e.g. 30 for 29.97, 60 for 59.94, 24 for 23.976)
        let exactFps = Double(num) / Double(den)
        let nominalFps = UInt64(max(Int( round(exactFps) ), 1))

        // Frame duration in nanoseconds: 1e9 * den / num
        let frameDurationNs = Double(1_000_000_000 * UInt64(den)) / Double(num)
        let totalFramesFloat = Double(taiNs) / max(frameDurationNs, 1.0)
        let frameIndex = UInt64(totalFramesFloat)
        let phase = max(0.0, min(0.999999, totalFramesFloat - Double(frameIndex)))

        // Compute HH:MM:SS:FF within 24-hour modulo with SMPTE ST 12-1 Drop-Frame support
        var displayFrameCount = frameIndex
        if isDF && (nominalFps == 30 || nominalFps == 60) {
            let dropFramesPerMinute: UInt64 = (nominalFps == 60) ? 4 : 2
            let framesPer10Min: UInt64 = nominalFps * 600 - dropFramesPerMinute * 9
            let framesPerMin: UInt64 = nominalFps * 60 - dropFramesPerMinute

            let d = frameIndex / framesPer10Min
            let m = frameIndex % framesPer10Min
            if m >= dropFramesPerMinute {
                displayFrameCount = frameIndex + dropFramesPerMinute * 9 * d + dropFramesPerMinute * ((m - dropFramesPerMinute) / framesPerMin)
            } else {
                displayFrameCount = frameIndex + dropFramesPerMinute * 9 * d
            }
        }

        let frames = UInt8(displayFrameCount % nominalFps)
        let totalSec = displayFrameCount / nominalFps
        let seconds = UInt8(totalSec % 60)
        let minutes = UInt8((totalSec / 60) % 60)
        let hours = UInt8((totalSec / 3600) % 24)

        let sep = isDF ? ";" : ":"
        let smpte = String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, sep, frames)
        let subframeHundredths = Int((phase * 100.0).rounded(.down)) % 100
        let smpteFull = String(format: "%@.%02d", smpte, subframeHundredths)
        let token = String(format: "%02d%02d%02d%02d", hours, minutes, seconds, frames)

        let bcdH = (UInt32(hours / 10) << 4) | UInt32(hours % 10)
        let bcdM = (UInt32(minutes / 10) << 4) | UInt32(minutes % 10)
        let bcdS = (UInt32(seconds / 10) << 4) | UInt32(seconds % 10)
        let bcdF = (UInt32(frames / 10) << 4) | UInt32(frames % 10)
        let bcd = (bcdH << 24) | (bcdM << 16) | (bcdS << 8) | bcdF

        let filename = "\(activeSensor)_\(token)_\(taiNs).\(fileExtension)"
        return OpticalMidpointStamp(
            sensorId: activeSensor,
            hostMachNanoseconds: hostMonoNs == 0 ? Self.currentMachNanoseconds() : hostMonoNs,
            disciplinedTaiNanoseconds: taiNs,
            smpteTimecode: smpte,
            smpteWithSubframe: smpteFull,
            bcdTimecode: bcd,
            subframePhase: phase,
            frameIndex: frameIndex,
            fpsNum: num,
            fpsDen: den,
            dropFrame: isDF,
            clockLockState: currentLock,
            captureFilename: filename
        )
    }

    // MARK: - Zero-Config Auto-Discovery (`UDP 50320` + HTTP `:7878`)

    /// Sends `"ABU_ECO_V1"` discovery probe to UDP port 50320 (subnet broadcast + target IP)
    /// and registers this iPhone with the Abu Clock Master.
    public func discoverAbuClockMaster(preferredHost: String? = nil, completion: ((AbuClockDiscoveryBeacon?) -> Void)? = nil) {
        clockQueue.async {
            let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard sock >= 0 else {
                completion?(nil)
                return
            }
            defer { close(sock) }

            var broadcastEnable: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))

            var timeout = timeval(tv_sec: 0, tv_usec: 450_000) // 450ms fast discovery timeout
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            let magicBytes = Array("ABU_ECO_V1".utf8)
            var candidateIPs = ["255.255.255.255"]
            if let preferred = preferredHost, !preferred.isEmpty, preferred != "255.255.255.255" {
                candidateIPs.insert(preferred, at: 0)
            }
            let configuredStreamIP = UDPStreamingManager.shared.streamIP
                .components(separatedBy: ",")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !configuredStreamIP.isEmpty && !candidateIPs.contains(configuredStreamIP) {
                candidateIPs.insert(configuredStreamIP, at: 0)
            }

            for ip in candidateIPs {
                var addr = sockaddr_in()
                #if os(iOS) || os(macOS)
                addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
                #endif
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = CFSwapInt16HostToBig(50320)
                addr.sin_addr.s_addr = inet_addr(ip)

                withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        magicBytes.withUnsafeBytes { rawBuf in
                            _ = sendto(sock, rawBuf.baseAddress, magicBytes.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
            }

            var recvBuf = [UInt8](repeating: 0, count: 4096)
            var fromAddr = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let bytesRead = withUnsafeMutablePointer(to: &fromAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    recvfrom(sock, &recvBuf, recvBuf.count - 1, 0, sockPtr, &fromLen)
                }
            }

            if bytesRead > 0 {
                let data = Data(recvBuf.prefix(bytesRead))
                if let beacon = try? JSONDecoder().decode(AbuClockDiscoveryBeacon.self, from: data) {
                    let resolvedIP: String
                    if beacon.master_ip == "127.0.0.1" || beacon.master_ip == "0.0.0.0" {
                        resolvedIP = String(cString: inet_ntoa(fromAddr.sin_addr))
                    } else {
                        resolvedIP = beacon.master_ip
                    }
                    self.applyDiscoveredBeacon(beacon, resolvedIP: resolvedIP)
                    self.registerNodeWithMaster(masterIP: resolvedIP, httpPort: beacon.http_api_port ?? 7878)
                    completion?(beacon)
                    return
                }
            }

            completion?(nil)
        }
    }

    private func applyDiscoveredBeacon(_ beacon: AbuClockDiscoveryBeacon, resolvedIP: String) {
        stateLock.lock()
        if let num = beacon.fps_num, num > 0 { self.fpsNum = num }
        if let den = beacon.fps_den, den > 0 { self.fpsDen = den }
        if let df = beacon.drop_frame { self.dropFrame = df }
        if let dom = beacon.ptp_domain { self.ptpDomain = dom }
        stateLock.unlock()

        DispatchQueue.main.async {
            self.discoveredMasterIP = resolvedIP
            if let num = beacon.fps_num, num > 0 { self.fpsNum = num }
            if let den = beacon.fps_den, den > 0 { self.fpsDen = den }
            if let df = beacon.drop_frame { self.dropFrame = df }
            if let dom = beacon.ptp_domain { self.ptpDomain = dom }

            // Auto-populate target IP if still on default placeholder
            if UDPStreamingManager.shared.streamIP == "192.168.1.100" && !resolvedIP.isEmpty {
                UDPStreamingManager.shared.streamIP = resolvedIP
            }
        }
    }

    private func registerNodeWithMaster(masterIP: String, httpPort: Int) {
        guard let url = URL(string: "http://\(masterIP):\(httpPort)/api/ecosystem/register") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 1.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let localIP = UDPStreamingManager.getLocalIPAddress()
        let exactFps = Double(fpsNum) / Double(max(fpsDen, 1))
        let payload: [String: Any] = [
            "node_id": "abutrack-ios-\(sensorId.lowercased())",
            "node_kind": "AbuTrackIos",
            "display_name": "Abu Track & Scan iOS (\(sensorId))",
            "platform": "iOS Swift (ARKit 60Hz + Metal + AbuClockKit)",
            "ip_address": localIP,
            "telemetry_port": UDPStreamingManager.shared.streamPort,
            "video_rtp_port": 5004,
            "clock_port": 50319,
            "control_http_port": 0,
            "protocols": [
                "LiveLink JSON (UDP \(UDPStreamingManager.shared.streamPort))",
                "FreeD 37B & 41B (0xD1/0xD2)",
                "OpenTrackIO (OTrk)",
                "RTP H.264/HEVC (UDP 5004)"
            ],
            "lock_state": lockState,
            "offset_ns": offsetNanoseconds,
            "frame_rate_str": String(format: "%.3f Hz (%@)", exactFps, dropFrame ? "DF" : "NDF"),
            "last_seen_tai_ns": nowTaiNanoseconds()
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    // MARK: - Unprivileged Port 50320 Stratum-1 SNTPv4 + 2-State Kalman Filter PLL

    /// Performs a high-precision SNTPv4 exchange against port 50320 (or fallback port 123)
    /// and updates the 2-state Kalman Filter PLL (`offsetNs`, `driftPpb`).
    public func performKalmanSNTPSync(
        serverIP: String,
        port: UInt16 = 50320,
        completion: ((Bool, Double) -> Void)? = nil
    ) {
        clockQueue.async {
            let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard sock >= 0 else {
                DispatchQueue.main.async { completion?(false, 0.0) }
                return
            }
            defer { close(sock) }

            var timeout = timeval(tv_sec: 0, tv_usec: 600_000) // 600ms timeout
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            var serverAddr = sockaddr_in()
            #if os(iOS) || os(macOS)
            serverAddr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
            #endif
            serverAddr.sin_family = sa_family_t(AF_INET)
            serverAddr.sin_port = CFSwapInt16HostToBig(port)
            serverAddr.sin_addr.s_addr = inet_addr(serverIP)

            if serverAddr.sin_addr.s_addr == 0xffffffff && serverIP != "255.255.255.255" {
                DispatchQueue.main.async { completion?(false, 0.0) }
                return
            }

            // 48-byte RFC 4330 SNTPv4 Client Request (LI=0, VN=4, Mode=3 -> 0x23)
            var packet = [UInt8](repeating: 0, count: 48)
            packet[0] = 0x23

            let t1MonoNs = Self.currentMachNanoseconds()
            let t1TaiEstNs = self.translateMachToTaiNanoseconds(t1MonoNs)

            let sent = withUnsafePointer(to: &serverAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    packet.withUnsafeBytes { rawBuf in
                        sendto(sock, rawBuf.baseAddress, 48, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent >= 48 else {
                DispatchQueue.main.async { completion?(false, 0.0) }
                return
            }

            var response = [UInt8](repeating: 0, count: 48)
            var fromAddr = sockaddr()
            var fromLen = socklen_t(MemoryLayout<sockaddr>.size)
            let recvLen = recvfrom(sock, &response, 48, 0, &fromAddr, &fromLen)
            let t4MonoNs = Self.currentMachNanoseconds()
            let t4TaiEstNs = self.translateMachToTaiNanoseconds(t4MonoNs)

            guard recvLen >= 48 else {
                // If port 50320 timed out, try fallback standard NTP port 123 once
                if port == 50320 {
                    self.performKalmanSNTPSync(serverIP: serverIP, port: 123, completion: completion)
                } else {
                    DispatchQueue.main.async { completion?(false, 0.0) }
                }
                return
            }

            func parseNtpToTaiNs(bytes: [UInt8], offset: Int) -> UInt64 {
                var secs: UInt32 = 0
                var frac: UInt32 = 0
                for i in 0..<4 {
                    secs = (secs << 8) | UInt32(bytes[offset + i])
                    frac = (frac << 8) | UInt32(bytes[offset + 4 + i])
                }
                let ntpEpochOffset: UInt64 = 2_208_988_800
                let unixSec = UInt64(secs) >= ntpEpochOffset ? (UInt64(secs) - ntpEpochOffset) : 0
                let taiSec = unixSec + UInt64(Self.taiMinusUtcSeconds)
                let fracNs = (UInt64(frac) * 1_000_000_000) >> 32
                return taiSec * 1_000_000_000 + fracNs
            }

            let t2ServerTaiNs = parseNtpToTaiNs(bytes: response, offset: 32)
            let t3ServerTaiNs = parseNtpToTaiNs(bytes: response, offset: 40)

            let rttNs = Double(Int64(bitPattern: t4MonoNs &- t1MonoNs) - Int64(bitPattern: t3ServerTaiNs &- t2ServerTaiNs))
            let measuredOffsetNs = (Double(Int64(bitPattern: t2ServerTaiNs &- t1TaiEstNs)) + Double(Int64(bitPattern: t3ServerTaiNs &- t4TaiEstNs))) * 0.5

            self.updateKalmanPLL(measuredOffsetNs: measuredOffsetNs, rttNs: max(rttNs, 1000.0), monoNowNs: t4MonoNs)

            let offsetSec = measuredOffsetNs * 1.0e-9
            DispatchQueue.main.async {
                self.discoveredMasterIP = serverIP
                self.rttMicroseconds = max(rttNs, 0.0) * 1.0e-3
                completion?(true, offsetSec)
            }
        }
    }

    private func updateKalmanPLL(measuredOffsetNs: Double, rttNs: Double, monoNowNs: UInt64) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let dtSec = max(Double(monoNowNs &- lastSyncMonoNs) * 1.0e-9, 0.05)
        lastSyncMonoNs = monoNowNs

        // First sample or large step (> 50ms): hard re-anchor to converge immediately
        if syncSampleCount == 0 || abs(measuredOffsetNs) > 50_000_000.0 {
            anchorTaiNs = UInt64(max(Int64(bitPattern: translateMachToTaiNanosecondsUnlocked(monoNowNs)) + Int64(measuredOffsetNs), 0))
            anchorMonoNs = monoNowNs
            kalmanOffsetNs = 0.0
            syncSampleCount += 1
            let newState = "Locked (AbuClock Master)"
            DispatchQueue.main.async {
                self.lockState = newState
                self.offsetNanoseconds = 0
            }
            return
        }

        // 2-State Kalman Filter Predict Step:
        // State vector x = [offset_ns, drift_ppb]^T
        let qOffset = 100.0 * dtSec
        let qDrift = 10.0 * dtSec
        let predOffset = kalmanOffsetNs + kalmanDriftPpb * dtSec
        let predDrift = kalmanDriftPpb

        let predP00 = p00 + dtSec * (p10 + p01) + (dtSec * dtSec) * p11 + qOffset
        let predP01 = p01 + dtSec * p11
        let predP10 = p10 + dtSec * p11
        let predP11 = p11 + qDrift

        // Measurement noise R scales with RTT^2 to reject Wi-Fi congestion spikes
        let rMeas = max((rttNs * 0.15) * (rttNs * 0.15), 2500.0)
        let innovation = measuredOffsetNs - predOffset
        let s = predP00 + rMeas
        let k0 = predP00 / s
        let k1 = predP10 / s

        kalmanOffsetNs = predOffset + k0 * innovation
        kalmanDriftPpb = max(-200_000.0, min(200_000.0, predDrift + k1 * innovation))

        p00 = (1.0 - k0) * predP00
        p01 = (1.0 - k0) * predP01
        p10 = predP10 - k1 * predP00
        p11 = predP11 - k1 * predP01
        syncSampleCount += 1

        let currentOffsetInt = Int64(kalmanOffsetNs)
        let currentDrift = kalmanDriftPpb
        DispatchQueue.main.async {
            self.lockState = "Locked (Kalman PLL)"
            self.offsetNanoseconds = currentOffsetInt
            self.driftPpb = currentDrift
        }
    }

    private func translateMachToTaiNanosecondsUnlocked(_ hostMonoNs: UInt64) -> UInt64 {
        let deltaNs = Double(Int64(bitPattern: hostMonoNs &- anchorMonoNs))
        let driftCorrection = deltaNs * (kalmanDriftPpb * 1.0e-9)
        let totalCorrection = Int64(deltaNs + driftCorrection + kalmanOffsetNs)
        let signedResult = Int64(bitPattern: anchorTaiNs) &+ totalCorrection
        return UInt64(max(signedResult, 0))
    }

    private func startContinuousKalmanSyncLoop() {
        let timer = DispatchSource.makeTimerSource(queue: clockQueue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.05) // 20 Hz UI timecode refresh + periodic network sync
        var tickCount = 0
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let stamp = self.stampMonotonicNanoseconds(Self.currentMachNanoseconds())
            let isFrameZero = stamp.smpteTimecode.hasSuffix(":00") || stamp.smpteTimecode.hasSuffix(";00")
            let bcdHexStr = String(format: "0x%08X", stamp.bcdTimecode)

            DispatchQueue.main.async {
                self.liveSmpteTimecode = stamp.smpteWithSubframe
                self.liveBcdHex = bcdHexStr
                self.liveSubframePhase = stamp.subframePhase
                self.liveTaiNanoseconds = stamp.disciplinedTaiNanoseconds
                self.isFlashMarkerFrameZero = isFrameZero
            }

            tickCount += 1
            // Every 2.0 seconds (40 ticks), run background discovery/Kalman SNTP sync if target IP is available
            if tickCount % 40 == 0 {
                let targetIP = !self.discoveredMasterIP.isEmpty
                    ? self.discoveredMasterIP
                    : (UDPStreamingManager.shared.streamIP.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                if !targetIP.isEmpty && targetIP != "255.255.255.255" {
                    self.performKalmanSNTPSync(serverIP: targetIP, port: 50320, completion: nil)
                } else if tickCount % 120 == 0 {
                    self.discoverAbuClockMaster(completion: nil)
                }
            }
        }
        timer.resume()
        self.syncTimer = timer
    }

    // MARK: - Future-Time Multi-Sensor Capture Barrier Listener (`UDP 50319`)

    private func startBarrierListenerOnPort50319() {
        guard !barrierListenerActive else { return }
        barrierListenerActive = true

        barrierQueue.async { [weak self] in
            guard let self = self else { return }
            let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard sock >= 0 else { return }
            self.barrierSocketFD = sock

            var reuse: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

            var bindAddr = sockaddr_in()
            #if os(iOS) || os(macOS)
            bindAddr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
            #endif
            bindAddr.sin_family = sa_family_t(AF_INET)
            bindAddr.sin_port = CFSwapInt16HostToBig(50319)
            bindAddr.sin_addr.s_addr = INADDR_ANY

            let bindRes = withUnsafePointer(to: &bindAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindRes < 0 {
                close(sock)
                self.barrierSocketFD = -1
                return
            }

            var buf = [UInt8](repeating: 0, count: 2048)
            while self.barrierListenerActive {
                var senderAddr = sockaddr_in()
                var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let readBytes = withUnsafeMutablePointer(to: &senderAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        recvfrom(sock, &buf, buf.count - 1, 0, sockPtr, &senderLen)
                    }
                }
                if readBytes > 0 {
                    let packetData = Data(buf.prefix(readBytes))
                    if let barrier = try? JSONDecoder().decode(AbuClockCaptureBarrier.self, from: packetData),
                       barrier.command == "SCHEDULE_CAPTURE_AT" {
                        let senderIP = String(cString: inet_ntoa(senderAddr.sin_addr))
                        self.executeScheduledBarrier(barrier, masterIP: senderIP)
                    }
                }
            }
        }
    }

    /// Executes a future-time `SCHEDULE_CAPTURE_AT` barrier using hybrid OS sleep + CPU spinlock
    /// so all iOS sensors (Camera + LiDAR) fire within < 50 microseconds of `target_tai_ns`.
    public func executeScheduledBarrier(_ barrier: AbuClockCaptureBarrier, masterIP: String) {
        barrierQueue.async { [weak self] in
            guard let self = self else { return }
            let nowTai = self.nowTaiNanoseconds()
            if barrier.target_tai_ns > nowTai {
                let remainingNs = barrier.target_tai_ns - nowTai
                // 1. Coarse OS sleep until 1.5 ms before target_tai_ns
                if remainingNs > 1_500_000 {
                    let sleepSec = Double(remainingNs - 1_500_000) * 1.0e-9
                    Thread.sleep(forTimeInterval: min(sleepSec, 2.0))
                }
                // 2. Deterministic CPU spinlock for the final 1.5 ms
                while self.nowTaiNanoseconds() < barrier.target_tai_ns {
                    // Tight hardware spinlock on mach_continuous_time
                }
            }

            let fireMonoNs = Self.currentMachNanoseconds()
            let stamp = self.stampMonotonicNanoseconds(fireMonoNs, fileExtension: (barrier.format ?? "dng").lowercased())
            let jitterNs = Int64(bitPattern: stamp.disciplinedTaiNanoseconds) - Int64(bitPattern: barrier.target_tai_ns)

            DispatchQueue.main.async {
                self.lastBarrierReceiptSummary = String(format: "SEQ #%llu // Jitter: %+lld ns (%@)", barrier.sequence_id, jitterNs, stamp.smpteTimecode)
                self.onScheduledCaptureTrigger?(barrier, stamp)
            }

            // Send CaptureReceipt back to Abu Clock Master HTTP API if reachable
            let receipt = AbuClockCaptureReceipt(
                sequence_id: barrier.sequence_id,
                sensor_id: self.sensorId,
                platform: "iOS-AbuClockKit",
                target_tai_ns: barrier.target_tai_ns,
                actual_tai_ns: stamp.disciplinedTaiNanoseconds,
                jitter_ns: jitterNs,
                filename: stamp.captureFilename,
                within_subframe_budget: abs(jitterNs) < 500_000
            )
            if !masterIP.isEmpty, let url = URL(string: "http://\(masterIP):7878/api/trigger/receipt") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONEncoder().encode(receipt)
                URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
            }
        }
    }
}
