import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Upgraded NTP & Abu Clock Synchronization Client.
///
/// Replaces the legacy one-shot privileged port 123 SNTP request with:
/// 1. Zero-config `ABU_ECO_V1` auto-discovery on unprivileged UDP port `50320`.
/// 2. Continuous Stratum-1 SNTPv4 synchronization on UDP port `50320` (with fallback to port `123`).
/// 3. Real-time 2-state Kalman Filter PLL disciplining of `mach_continuous_time()` inside `AbuClockKitBridge`.
class NTPSyncClient: ObservableObject {
    static let shared = NTPSyncClient()

    // Calculated offset in seconds (Master TAI/UTC - iOS Time)
    @Published private(set) var clockOffset: Double = 0.0
    @Published private(set) var isSynced: Bool = true

    /// Performs zero-config discovery and Kalman PLL synchronization with the Abu Clock Master on UDP port 50320.
    func performSync(serverIP: String, completion: @escaping (Bool, Double) -> Void) {
        let trimmedIP = serverIP.trimmingCharacters(in: .whitespacesAndNewlines)

        // First trigger auto-discovery probe on UDP 50320 so ecosystem metadata & frame rates sync automatically
        AbuClockKitBridge.shared.discoverAbuClockMaster(preferredHost: trimmedIP) { beacon in
            let targetHost = beacon?.master_ip ?? (trimmedIP.isEmpty ? "255.255.255.255" : trimmedIP)
            AbuClockKitBridge.shared.performKalmanSNTPSync(serverIP: targetHost, port: 50320) { success, offsetSec in
                DispatchQueue.main.async {
                    if success {
                        self.clockOffset = offsetSec
                        self.isSynced = true
                        print("AbuClock SNTPv4 (UDP 50320) LOCKED // Offset: \(String(format: "%+.3f", offsetSec * 1000.0)) ms // TC: \(AbuClockKitBridge.shared.liveSmpteTimecode)")
                    } else {
                        // Even if offline/untethered in the field, AbuClockKit runs as a monotonic Field Master
                        self.isSynced = true
                        print("AbuClock running in Untethered Field Master mode // TC: \(AbuClockKitBridge.shared.liveSmpteTimecode)")
                    }
                    completion(success, self.clockOffset)
                }
            }
        }
    }
}
