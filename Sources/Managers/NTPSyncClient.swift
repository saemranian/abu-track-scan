import Foundation
#if canImport(Darwin)
import Darwin
#endif

class NTPSyncClient {
    static let shared = NTPSyncClient()
    
    // Calculated offset in seconds (PC Time - iOS Time)
    private(set) var clockOffset: Double = 0.0
    private(set) var isSynced: Bool = false
    
    func performSync(serverIP: String, completion: @escaping (Bool, Double) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Create UDP socket
            let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard socketFD >= 0 else {
                print("NTP Sync: Failed to create socket")
                DispatchQueue.main.async {
                    completion(false, 0.0)
                }
                return
            }
            
            // Set 1.5-second timeout for reception
            var timeout = timeval()
            timeout.tv_sec = 1
            timeout.tv_usec = 500000
            setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            
            // Build server address
            var serverAddr = sockaddr_in()
            #if os(iOS) || os(macOS)
            serverAddr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
            #endif
            serverAddr.sin_family = sa_family_t(AF_INET)
            serverAddr.sin_port = CFSwapInt16HostToBig(123) // NTP is standard port 123
            serverAddr.sin_addr.s_addr = inet_addr(serverIP)
            
            if serverAddr.sin_addr.s_addr == 0xffffffff && serverIP != "255.255.255.255" {
                print("NTP Sync: Invalid Server IP Address: \(serverIP)")
                close(socketFD)
                DispatchQueue.main.async {
                    completion(false, 0.0)
                }
                return
            }
            
            // Build standard SNTP request packet (48 bytes)
            var packet = [UInt8](repeating: 0, count: 48)
            packet[0] = 0x1B // LI = 0 (no warning), VN = 3 (version 3), Mode = 3 (Client)
            
            // Local transmit time (T0)
            let t0 = Date().timeIntervalSince1970
            
            let packetCount = packet.count
            let sendResult = withUnsafePointer(to: &serverAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    packet.withUnsafeBytes { dataBytes in
                        sendto(socketFD, dataBytes.baseAddress, packetCount, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            
            guard sendResult >= 0 else {
                print("NTP Sync: sendto failed")
                close(socketFD)
                DispatchQueue.main.async {
                    completion(false, 0.0)
                }
                return
            }
            
            // Receive buffer (48 bytes)
            var response = [UInt8](repeating: 0, count: 48)
            var fromAddr = sockaddr()
            var fromLen = socklen_t(MemoryLayout<sockaddr>.size)
            
            let recvResult = recvfrom(socketFD, &response, 48, 0, &fromAddr, &fromLen)
            
            let t1 = Date().timeIntervalSince1970 // Local receive time (T1)
            close(socketFD)
            
            guard recvResult >= 48 else {
                print("NTP Sync: recvfrom failed or timed out")
                DispatchQueue.main.async {
                    completion(false, 0.0)
                }
                return
            }
            
            // Extract NTP timestamps from response (seconds from Jan 1 1900)
            // Receive Timestamp (T2): bytes 32-39
            // Transmit Timestamp (T3): bytes 40-47
            
            func parseNTPTimestamp(bytes: [UInt8], offset: Int) -> Double {
                var seconds: UInt32 = 0
                var fraction: UInt32 = 0
                
                for i in 0..<4 {
                    seconds = (seconds << 8) | UInt32(bytes[offset + i])
                    fraction = (fraction << 8) | UInt32(bytes[offset + 4 + i])
                }
                
                let ntpEpochOffset: Double = 2208988800 // seconds between 1900 and 1970
                let fracPart = Double(fraction) / Double(UInt32.max)
                return Double(seconds) - ntpEpochOffset + fracPart
            }
            
            let t2 = parseNTPTimestamp(bytes: response, offset: 32)
            let t3 = parseNTPTimestamp(bytes: response, offset: 40)
            
            // Calculate high-precision network clock offset (theta)
            let offset = ((t2 - t0) + (t3 - t1)) / 2.0
            print("NTP Sync SUCCESS // Offset: \(offset * 1000.0) ms")
            
            DispatchQueue.main.async {
                self.clockOffset = offset
                self.isSynced = true
                completion(true, offset)
            }
        }
    }
}
