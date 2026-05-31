import Foundation
import Network
import Combine
#if canImport(Darwin)
import Darwin
#endif

enum StreamingFormat: String, CaseIterable, Identifiable {
    case liveLink = "Live Link JSON"
    case freeD = "FreeD Binary"
    case openTrackIO = "OpenTrackIO JSON"
    
    var id: String { self.rawValue }
}

struct TargetEndpoint {
    let ip: String
    let port: Int
}

class BSDUDPSender {
    private var socketFD: Int32 = -1
    private var targets: [(sockaddr_in, String, Int)] = []
    
    func setup(endpoints: [TargetEndpoint]) {
        closeSocket()
        
        // Create UDP socket
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            AppLogger.critical("BSD UDP: Failed to create socket")
            return
        }
        
        // Enable broadcast
        var broadcastEnable: Int32 = 1
        let setOptResult = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))
        if setOptResult < 0 {
            AppLogger.error("BSD UDP: Failed to set SO_BROADCAST")
        }
        
        self.socketFD = fd
        
        // Bind to 0.0.0.0 (INADDR_ANY) to let the iOS kernel configure standard interface routing for UDP broadcasts
        var localAddr = sockaddr_in()
        #if os(iOS) || os(macOS)
        localAddr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        #endif
        localAddr.sin_family = sa_family_t(AF_INET)
        localAddr.sin_port = CFSwapInt16HostToBig(0) // system selects available port
        localAddr.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY (0.0.0.0)
        
        let bindResult = withUnsafePointer(to: &localAddr) { localAddrPtr in
            localAddrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult < 0 {
            AppLogger.error("BSD UDP: Socket bind to 0.0.0.0 failed with error \(errno) (\(String(cString: strerror(errno))))")
        }
        
        // Resolve IP addresses and prepare sockaddr_in structs
        for endpoint in endpoints {
            var addr = sockaddr_in()
            #if os(iOS) || os(macOS)
            addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
            #endif
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = CFSwapInt16HostToBig(UInt16(endpoint.port))
            
            let ipAddressStr = endpoint.ip
            let resolved = inet_addr(ipAddressStr)
            if resolved == 0xffffffff && ipAddressStr != "255.255.255.255" {
                AppLogger.warning("BSD UDP: Invalid IP address: \(ipAddressStr)")
                continue
            }
            addr.sin_addr.s_addr = resolved
            
            targets.append((addr, endpoint.ip, endpoint.port))
            AppLogger.info("BSD UDP: Configured destination \(endpoint.ip):\(endpoint.port) [SO_BROADCAST enabled]")
        }
    }
    
    func send(data: Data) {
        guard socketFD >= 0 else { return }
        
        for (addr, ip, port) in targets {
            var targetAddr = addr
            let dataCount = data.count
            
            let result = withUnsafePointer(to: &targetAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    data.withUnsafeBytes { dataBytes in
                        sendto(socketFD, dataBytes.baseAddress, dataCount, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if result < 0 {
                let err = errno
                AppLogger.error("BSD UDP: sendto failed to \(ip):\(port) with error \(err) (\(String(cString: strerror(err))))")
            }
        }
    }
    
    func closeSocket() {
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        targets.removeAll()
    }
    
    deinit {
        closeSocket()
    }
}

class UDPStreamingManager: ObservableObject {
    static let shared = UDPStreamingManager()
    
    @Published var isStreamingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isStreamingEnabled, forKey: "isStreamingEnabled")
            if isStreamingEnabled {
                startConnection()
            } else {
                stopConnection()
            }
        }
    }
    
    @Published var streamIP: String {
        didSet {
            UserDefaults.standard.set(streamIP, forKey: "streamIP")
            restartConnection()
        }
    }
    
    @Published var streamPort: Int {
        didSet {
            UserDefaults.standard.set(streamPort, forKey: "streamPort")
            restartConnection()
        }
    }
    
    @Published var isBroadcastEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBroadcastEnabled, forKey: "isBroadcastEnabled")
            restartConnection()
        }
    }
    
    @Published var format: StreamingFormat {
        didSet {
            UserDefaults.standard.set(format.rawValue, forKey: "streamingFormat")
        }
    }
    
    // Coordinate Alignment Profile
    @Published var coordinatePreset: String {
        didSet { UserDefaults.standard.set(coordinatePreset, forKey: "coordinatePreset") }
    }
    @Published var xMapSource: String { didSet { UserDefaults.standard.set(xMapSource, forKey: "xMapSource") } }
    @Published var yMapSource: String { didSet { UserDefaults.standard.set(yMapSource, forKey: "yMapSource") } }
    @Published var zMapSource: String { didSet { UserDefaults.standard.set(zMapSource, forKey: "zMapSource") } }
    
    @Published var xMapSign: Double { didSet { UserDefaults.standard.set(xMapSign, forKey: "xMapSign") } }
    @Published var yMapSign: Double { didSet { UserDefaults.standard.set(yMapSign, forKey: "yMapSign") } }
    @Published var zMapSign: Double { didSet { UserDefaults.standard.set(zMapSign, forKey: "zMapSign") } }
    
    @Published var rollMapSource: String { didSet { UserDefaults.standard.set(rollMapSource, forKey: "rollMapSource") } }
    @Published var pitchMapSource: String { didSet { UserDefaults.standard.set(pitchMapSource, forKey: "pitchMapSource") } }
    @Published var yawMapSource: String { didSet { UserDefaults.standard.set(yawMapSource, forKey: "yawMapSource") } }
    
    @Published var rollMapSign: Double { didSet { UserDefaults.standard.set(rollMapSign, forKey: "rollMapSign") } }
    @Published var pitchMapSign: Double { didSet { UserDefaults.standard.set(pitchMapSign, forKey: "pitchMapSign") } }
    @Published var yawMapSign: Double { didSet { UserDefaults.standard.set(yawMapSign, forKey: "yawMapSign") } }
    
    private var bsdSender = BSDUDPSender()
    private let queue = DispatchQueue(label: "com.abutrack.udpstreaming", qos: .userInteractive)
    
    private init() {
        self.isStreamingEnabled = UserDefaults.standard.bool(forKey: "isStreamingEnabled")
        self.streamIP = UserDefaults.standard.string(forKey: "streamIP") ?? "192.168.1.100"
        self.streamPort = UserDefaults.standard.integer(forKey: "streamPort") == 0 ? 8080 : UserDefaults.standard.integer(forKey: "streamPort")
        self.isBroadcastEnabled = UserDefaults.standard.bool(forKey: "isBroadcastEnabled")
        
        let formatStr = UserDefaults.standard.string(forKey: "streamingFormat") ?? StreamingFormat.liveLink.rawValue
        self.format = StreamingFormat(rawValue: formatStr) ?? .liveLink
        
        self.coordinatePreset = UserDefaults.standard.string(forKey: "coordinatePreset") ?? "Default (ARKit)"
        self.xMapSource = UserDefaults.standard.string(forKey: "xMapSource") ?? "X"
        self.yMapSource = UserDefaults.standard.string(forKey: "yMapSource") ?? "Y"
        self.zMapSource = UserDefaults.standard.string(forKey: "zMapSource") ?? "Z"
        
        self.xMapSign = UserDefaults.standard.double(forKey: "xMapSign") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "xMapSign")
        self.yMapSign = UserDefaults.standard.double(forKey: "yMapSign") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "yMapSign")
        self.zMapSign = UserDefaults.standard.double(forKey: "zMapSign") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "zMapSign")
        
        self.rollMapSource = UserDefaults.standard.string(forKey: "rollMapSource") ?? "Roll"
        self.pitchMapSource = UserDefaults.standard.string(forKey: "pitchMapSource") ?? "Pitch"
        self.yawMapSource = UserDefaults.standard.string(forKey: "yawMapSource") ?? "Yaw"
        
        self.rollMapSign = UserDefaults.standard.double(forKey: "rollMapSign") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "rollMapSign")
        self.pitchMapSign = UserDefaults.standard.double(forKey: "pitchMapSign") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "pitchMapSign")
        self.yawMapSign = UserDefaults.standard.double(forKey: "yawMapSign") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "yawMapSign")
        
        if isStreamingEnabled {
            startConnection()
        }
    }
    
    private func startConnection() {
        guard isStreamingEnabled else { return }
        
        AppLogger.info("Starting UDP Telemetry Stream (IP: \(streamIP), Port: \(streamPort), Broadcast: \(isBroadcastEnabled))")
        
        // Build the target endpoints
        var endpoints: [TargetEndpoint] = []
        
        if isBroadcastEnabled {
            endpoints.append(TargetEndpoint(ip: "255.255.255.255", port: streamPort))
        } else {
            // Split by comma for multiple targets
            let ipComponents = streamIP.components(separatedBy: ",")
            for comp in ipComponents {
                let trimmed = comp.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                
                if trimmed.contains(":") {
                    let parts = trimmed.components(separatedBy: ":")
                    if parts.count == 2, let customPort = Int(parts[1]) {
                        endpoints.append(TargetEndpoint(ip: parts[0], port: customPort))
                    } else {
                        endpoints.append(TargetEndpoint(ip: parts[0], port: streamPort))
                    }
                } else {
                    endpoints.append(TargetEndpoint(ip: trimmed, port: streamPort))
                }
            }
        }
        
        // Stop any old connections first
        stopConnection()
        
        // Setup raw POSIX socket connection
        bsdSender.setup(endpoints: endpoints)
    }
    
    private func stopConnection() {
        AppLogger.info("Stopping telemetry socket stream.")
        bsdSender.closeSocket()
    }
    
    private func restartConnection() {
        stopConnection()
        startConnection()
    }
    
    func stream(x: Double, y: Double, z: Double, yaw: Double, pitch: Double, roll: Double, newPoints: [RawPoint3D]? = nil, isMappingActive: Bool = true) {
        guard isStreamingEnabled else { return }
        
        var tx = x
        var ty = y
        var tz = z
        var mYaw = yaw
        var mPitch = pitch
        var mRoll = roll
        
        switch coordinatePreset {
        case "Default (ARKit)":
            break
        case "Unreal Engine":
            tx = x
            ty = z
            tz = y
            mYaw = yaw
            mPitch = pitch
            mRoll = roll
        case "Metashape":
            tx = x
            ty = -z
            tz = y
            mYaw = yaw
            mPitch = pitch
            mRoll = roll
        case "Custom":
            let inputs = ["X": x, "Y": y, "Z": z]
            tx = (inputs[xMapSource] ?? x) * xMapSign
            ty = (inputs[yMapSource] ?? y) * yMapSign
            tz = (inputs[zMapSource] ?? z) * zMapSign
            
            let rotInputs = ["Roll": roll, "Pitch": pitch, "Yaw": yaw]
            mRoll = (rotInputs[rollMapSource] ?? roll) * rollMapSign
            mPitch = (rotInputs[pitchMapSource] ?? pitch) * pitchMapSign
            mYaw = (rotInputs[yawMapSource] ?? yaw) * yawMapSign
        default:
            break
        }
        
        
        let data: Data
        
        switch format {
        case .liveLink:
            data = formatLiveLink(x: tx, y: ty, z: tz, yaw: mYaw, pitch: mPitch, roll: mRoll, newPoints: newPoints, isMappingActive: isMappingActive)
        case .freeD:
            data = formatFreeD(x: tx, y: ty, z: tz, yaw: mYaw, pitch: mPitch, roll: mRoll)
        case .openTrackIO:
            data = formatOpenTrackIO(x: tx, y: ty, z: tz, yaw: mYaw, pitch: mPitch, roll: mRoll, newPoints: newPoints, isMappingActive: isMappingActive)
        }
        
        // Broadcast the formatted tracking payload to all active connections
        bsdSender.send(data: data)
    }
    
    private func formatLiveLink(x: Double, y: Double, z: Double, yaw: Double, pitch: Double, roll: Double, newPoints: [RawPoint3D]? = nil, isMappingActive: Bool = true) -> Data {
        let ntpSyncOffset = NTPSyncClient.shared.isSynced ? NTPSyncClient.shared.clockOffset : 0.0
        var json: [String: Any] = [
            "deviceName": "AbuTrack",
            "translation": [x, y, z],
            "rotation": [pitch, yaw, roll],
            "focalLength": 24.0,
            "timestamp": Date().timeIntervalSince1970 + ntpSyncOffset,
            "isMappingActive": isMappingActive
        ]
        if let pts = newPoints, !pts.isEmpty {
            json["new_points"] = pts.map { [$0.x, $0.y, $0.z] }
        }
        
        do {
            return try JSONSerialization.data(withJSONObject: json, options: [])
        } catch {
            return Data()
        }
    }
    
    private func formatFreeD(x: Double, y: Double, z: Double, yaw: Double, pitch: Double, roll: Double) -> Data {
        var packet = [UInt8]()
        
        // Byte 0: Message Type (0xD1)
        packet.append(0xD1)
        
        // Byte 1: Camera ID (0x01)
        packet.append(0x01)
        
        // Byte 2-4: Pitch (signed 24-bit integer, scale 32768.0)
        let pitchVal = Int32(clamp(pitch * 32768.0, min: -8388607.0, max: 8388607.0))
        packet.append(contentsOf: pack24(pitchVal))
        
        // Byte 5-7: Yaw (signed 24-bit integer, scale 32768.0)
        let yawVal = Int32(clamp(yaw * 32768.0, min: -8388607.0, max: 8388607.0))
        packet.append(contentsOf: pack24(yawVal))
        
        // Byte 8-10: Roll (signed 24-bit integer, scale 32768.0)
        let rollVal = Int32(clamp(roll * 32768.0, min: -8388607.0, max: 8388607.0))
        packet.append(contentsOf: pack24(rollVal))
        
        // SPEC COMPLIANT FREED D1 COORDINATE ORDERING:
        // Byte 11-13: Z position (signed 24-bit integer, scale 64.0 per mm, translation is in meters)
        let zVal = Int32(clamp(z * 1000.0 * 64.0, min: -8388607.0, max: 8388607.0))
        packet.append(contentsOf: pack24(zVal))
        
        // Byte 14-16: X position (signed 24-bit integer, scale 64.0 per mm)
        let xVal = Int32(clamp(x * 1000.0 * 64.0, min: -8388607.0, max: 8388607.0))
        packet.append(contentsOf: pack24(xVal))
        
        // Byte 17-19: Y position (signed 24-bit integer, scale 64.0 per mm)
        let yVal = Int32(clamp(y * 1000.0 * 64.0, min: -8388607.0, max: 8388607.0))
        packet.append(contentsOf: pack24(yVal))
        
        // Byte 20-22: Zoom (24-bit unsigned integer, set to 0)
        packet.append(contentsOf: [0x00, 0x00, 0x00])
        
        // Byte 23-25: Focus (24-bit unsigned integer, set to 0)
        packet.append(contentsOf: [0x00, 0x00, 0x00])
        
        // Byte 26-27: Reserved (0x0000)
        packet.append(contentsOf: [0x00, 0x00])
        
        // Byte 28: Checksum
        // The checksum is calculated as: checksum = (0x40 - sum) & 0xFF
        var sum: Int = 0
        for byte in packet {
            sum += Int(byte)
        }
        let checksum = UInt8((0x40 - sum) & 0xFF)
        packet.append(checksum)
        
        // Proprietary Extended FreeD: Append an 8-byte big-endian millisecond timestamp for clock sync latency calculations!
        let ntpSyncOffset = NTPSyncClient.shared.isSynced ? NTPSyncClient.shared.clockOffset : 0.0
        let timestampMs = Int64((Date().timeIntervalSince1970 + ntpSyncOffset) * 1000.0)
        var tsBig = timestampMs.bigEndian
        packet.append(contentsOf: withUnsafeBytes(of: &tsBig) { Array($0) })
        
        return Data(packet)
    }
    
    private var openTrackSequence: UInt32 = 0
    
    private func formatOpenTrackIO(x: Double, y: Double, z: Double, yaw: Double, pitch: Double, roll: Double, newPoints: [RawPoint3D]? = nil, isMappingActive: Bool = true) -> Data {
        let ntpSyncOffset = NTPSyncClient.shared.isSynced ? NTPSyncClient.shared.clockOffset : 0.0
        let timestamp = Date().timeIntervalSince1970 + ntpSyncOffset
        
        var json: [String: Any] = [
            "version": "1.0",
            "sourceId": 101,
            "timestamp": timestamp,
            "isMappingActive": isMappingActive,
            "transforms": [
                [
                    "translation": ["x": x, "y": y, "z": z],
                    "rotation": ["yaw": yaw, "pitch": pitch, "roll": roll]
                ]
            ],
            "lens": [
                "focalLength": 24.0,
                "focusDistance": 1.5
            ]
        ]
        if let pts = newPoints, !pts.isEmpty {
            json["new_points"] = pts.map { [$0.x, $0.y, $0.z] }
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            return Data()
        }
        
        var packet = Data()
        
        // 1. Fixed ASCII Header: "OTrk" (4 bytes)
        packet.append("OTrk".data(using: .ascii)!)
        
        // 2. Sequence number (4 bytes, big-endian)
        openTrackSequence += 1
        var seqBig = openTrackSequence.bigEndian
        packet.append(contentsOf: withUnsafeBytes(of: &seqBig) { Array($0) })
        
        // 3. Payload Type: JSON is 0x01 (1 byte)
        packet.append(0x01)
        
        // 4. Payload Length (4 bytes, big-endian)
        var lenBig = UInt32(jsonData.count).bigEndian
        packet.append(contentsOf: withUnsafeBytes(of: &lenBig) { Array($0) })
        
        // 5. Source ID: 101 (4 bytes, big-endian)
        var srcBig = UInt32(101).bigEndian
        packet.append(contentsOf: withUnsafeBytes(of: &srcBig) { Array($0) })
        
        // 6. JSON Data
        packet.append(jsonData)
        
        return packet
    }
    
    private func pack24(_ value: Int32) -> [UInt8] {
        let b1 = UInt8((value >> 16) & 0xFF)
        let b2 = UInt8((value >> 8) & 0xFF)
        let b3 = UInt8(value & 0xFF)
        return [b1, b2, b3]
    }
    
    private func clamp(_ val: Double, min minVal: Double, max maxVal: Double) -> Double {
        return max(minVal, min(maxVal, val))
    }
    
    // Static helper to query the device's local network interface IP (both Wi-Fi en0 and Ethernet adapters)
    static func getLocalIPAddress() -> String {
        var address: String = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let addr = ptr.pointee.ifa_addr.pointee
            if addr.sa_family == UInt8(AF_INET) {
                let name = String(cString: ptr.pointee.ifa_name)
                // Filter out loopback, check for Wi-Fi (en0) or LAN dongles (en1, en2, eth0)
                if name.hasPrefix("en") || name.hasPrefix("eth") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if !ip.isEmpty && ip != "127.0.0.1" {
                            address = ip
                            break
                        }
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
