import Foundation
import Network
import Combine
#if canImport(Darwin)
import Darwin
#endif

enum StreamingFormat: String, CaseIterable, Identifiable {
    case liveLink = "Live Link JSON"
    case freeD = "FreeD Binary"
    
    var id: String { self.rawValue }
}

struct TargetEndpoint {
    let ip: String
    let port: Int
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
    
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.abutrack.udpstreaming", qos: .userInteractive)
    
    private init() {
        self.isStreamingEnabled = UserDefaults.standard.bool(forKey: "isStreamingEnabled")
        self.streamIP = UserDefaults.standard.string(forKey: "streamIP") ?? "192.168.1.100"
        self.streamPort = UserDefaults.standard.integer(forKey: "streamPort") == 0 ? 8080 : UserDefaults.standard.integer(forKey: "streamPort")
        self.isBroadcastEnabled = UserDefaults.standard.bool(forKey: "isBroadcastEnabled")
        
        let formatStr = UserDefaults.standard.string(forKey: "streamingFormat") ?? StreamingFormat.liveLink.rawValue
        self.format = StreamingFormat(rawValue: formatStr) ?? .liveLink
        
        if isStreamingEnabled {
            startConnection()
        }
    }
    
    private func startConnection() {
        guard isStreamingEnabled else { return }
        
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
        
        // Spin up NWConnections for all target endpoints
        for endpoint in endpoints {
            let host = NWEndpoint.Host(endpoint.ip)
            guard let portValue = NWEndpoint.Port(rawValue: UInt16(endpoint.port)) else { continue }
            
            let params = NWParameters.udp
            // Optimize for ultimate low latency: priority voice class + bypass intermediate queues
            params.serviceClass = .interactiveVoice
            params.preferNoProxies = true
            params.allowLocalMulticast = true
            
            let connection = NWConnection(to: NWEndpoint.hostPort(host: host, port: portValue), using: params)
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("UDP Streamer: Connected to \(endpoint.ip):\(endpoint.port) [Mode: \(self.isBroadcastEnabled ? "Broadcast" : "Unicast")]")
                case .failed(let error):
                    print("UDP Streamer: Connection failed to \(endpoint.ip):\(endpoint.port): \(error)")
                case .cancelled:
                    print("UDP Streamer: Connection cancelled to \(endpoint.ip):\(endpoint.port)")
                default:
                    break
                }
            }
            
            connection.start(queue: queue)
            connections.append(connection)
        }
    }
    
    private func stopConnection() {
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
    }
    
    private func restartConnection() {
        stopConnection()
        startConnection()
    }
    
    func stream(x: Double, y: Double, z: Double, yaw: Double, pitch: Double, roll: Double) {
        guard isStreamingEnabled, !connections.isEmpty else { return }
        
        let data: Data
        
        switch format {
        case .liveLink:
            data = formatLiveLink(x: x, y: y, z: z, yaw: yaw, pitch: pitch, roll: roll)
        case .freeD:
            data = formatFreeD(x: x, y: y, z: z, yaw: yaw, pitch: pitch, roll: roll)
        }
        
        // Broadcast the formatted tracking payload to all active connections
        for conn in connections {
            conn.send(content: data, completion: .contentProcessed({ error in
                if let error = error {
                    print("UDP Streamer: Send error: \(error)")
                }
            }))
        }
    }
    
    private func formatLiveLink(x: Double, y: Double, z: Double, yaw: Double, pitch: Double, roll: Double) -> Data {
        let json: [String: Any] = [
            "deviceName": "AbuTrack",
            "translation": [x, y, z],
            "rotation": [pitch, yaw, roll],
            "focalLength": 24.0,
            "timestamp": Date().timeIntervalSince1970
        ]
        
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
        
        // Byte 11-13: X position (signed 24-bit integer, scale 64.0 per mm, translation is in meters)
        let xVal = Int32(clamp(x * 1000.0 * 64.0, min: -8388607.0, max: 8388607.0))
        packet.append(contentsOf: pack24(xVal))
        
        // Byte 14-16: Y position (signed 24-bit integer, scale 64.0 per mm)
        let yVal = Int32(clamp(y * 1000.0 * 64.0, min: -8388607.0, max: 8388607.0))
        packet.append(contentsOf: pack24(yVal))
        
        // Byte 17-19: Z position (signed 24-bit integer, scale 64.0 per mm)
        let zVal = Int32(clamp(z * 1000.0 * 64.0, min: -8388607.0, max: 8388607.0))
        packet.append(contentsOf: pack24(zVal))
        
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
        
        return Data(packet)
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
        
        for ptr in sequence(firstAddr, next: { $0.pointee.ifa_next }) {
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
