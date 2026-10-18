import SwiftUI

/// Full-Screen Digital Clapper Slate & Sub-Microsecond Optical Calibration Beacon
/// powered by `AbuClockKitBridge`.
///
/// Designed for both:
/// 1. **Abu Scan**: Photographing the slate once with an external DSLR/Mirrorless camera
///    calibrates the DSLR's internal EXIF RTC crystal offset to < 1 ms using the Frame-00
///    Optical Flash Marker and calibrated Sub-Frame Phase Sweep Bar (phi in [0.0, 1.0)).
/// 2. **Abu Track**: Slating secondary iOS cameras, Cinema cameras, and Unreal Engine 5
///    Take Recorder / LiveLink takes with SMPTE ST 12-1 / ST 2059-2 timecode.
struct AbuClockSlateView: View {
    @ObservedObject var clockBridge = AbuClockKitBridge.shared
    @Environment(\.dismiss) private var dismiss

    @State private var manualClapActive: Bool = false
    @State private var selectedFpsPreset: String = "29.97 DF"
    @State private var discoveryStatusText: String = "UDP 50320 Stratum-1 + ABU_ECO_V1 Ready"

    private let fpsPresets: [(label: String, num: UInt32, den: UInt32, df: Bool)] = [
        ("23.976 NDF", 24000, 1001, false),
        ("24.00 NDF", 24, 1, false),
        ("25.00 PAL", 25, 1, false),
        ("29.97 DF", 30000, 1001, true),
        ("30.00 NDF", 30, 1, false),
        ("50.00 PAL", 50, 1, false),
        ("59.94 DF", 60000, 1001, true),
        ("60.00 NDF", 60, 1, false)
    ]

    var body: some View {
        ZStack {
            // High-contrast background that flashes white during manual clap
            (manualClapActive ? Color.white : Color(red: 0.02, green: 0.03, blue: 0.06))
                .ignoresSafeArea()

            VStack(spacing: 14) {
                // Top Clapper Sticks Header
                clapperSticksHeader

                // Main SMPTE Timecode Readout Card
                VStack(spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(clockBridge.lockState.contains("Locked") ? Color.green : Color.orange)
                                .frame(width: 9, height: 9)
                            Text("ABU CLOCK // \(clockBridge.lockState.uppercased())")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                        Spacer()
                        Text("BCD \(clockBridge.liveBcdHex)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                    }

                    // Giant Monospaced SMPTE Timecode
                    Text(clockBridge.liveSmpteTimecode)
                        .font(.system(size: 42, weight: .black, design: .monospaced))
                        .foregroundColor(manualClapActive ? .black : (clockBridge.isFlashMarkerFrameZero ? .yellow : .white))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.vertical, 4)

                    HStack {
                        Text("TAI: \(clockBridge.liveTaiNanoseconds) ns")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "PHASE φ: %.4f  |  DRIFT: %+.1f ppb", clockBridge.liveSubframePhase, clockBridge.driftPpb))
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(14)
                .background(Color(red: 0.05, green: 0.07, blue: 0.14))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(clockBridge.isFlashMarkerFrameZero ? Color.yellow : Color.cyan.opacity(0.4), lineWidth: clockBridge.isFlashMarkerFrameZero ? 2.5 : 1)
                )

                // FRAME-00 OPTICAL FLASH MARKER & SUB-FRAME PHASE SWEEP BAR
                opticalCalibrationBar

                // Production / Scene / Take / FPS Metadata Grid
                slateMetadataGrid

                // FPS Selector Row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(fpsPresets, id: \.label) { preset in
                            Button(action: {
                                selectedFpsPreset = preset.label
                                clockBridge.fpsNum = preset.num
                                clockBridge.fpsDen = preset.den
                                clockBridge.dropFrame = preset.df
                            }) {
                                Text(preset.label)
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(selectedFpsPreset == preset.label ? .black : .white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedFpsPreset == preset.label ? Color.cyan : Color.white.opacity(0.08))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }

                // Action Buttons: Auto-Discover Master, Clap Flash, & Close
                HStack(spacing: 10) {
                    Button(action: {
                        discoveryStatusText = "Broadcasting ABU_ECO_V1 on UDP 50320..."
                        clockBridge.discoverAbuClockMaster { beacon in
                            DispatchQueue.main.async {
                                if let b = beacon {
                                    discoveryStatusText = "LOCKED TO MASTER @ \(b.master_ip):50320"
                                } else {
                                    discoveryStatusText = "FIELD MASTER MODE (No PC on LAN)"
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("AUTO-SYNC (50320)")
                        }
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.cyan)
                        .cornerRadius(8)
                    }

                    Button(action: {
                        triggerManualOpticalClap()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                            Text("CLAP / FLASH SLATE")
                        }
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.yellow)
                        .cornerRadius(8)
                    }
                }

                Text(discoveryStatusText)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
    }

    private var clapperSticksHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ABU CLOCK // DIGITAL CLAPPER SLATE")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                Text("SMPTE ST 12-1 / ST 2059-2 OPTICAL & PTP GENLOCK BEACON")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            Spacer()
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                    Text("EXIT SLATE")
                }
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.8))
                .cornerRadius(6)
            }
        }
    }

    private var opticalCalibrationBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Frame-00 High-Contrast Optical Flash Target
                VStack(spacing: 2) {
                    Text(clockBridge.isFlashMarkerFrameZero || manualClapActive ? "FRAME 00 FLASH" : "OPTICAL TARGET")
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .foregroundColor(clockBridge.isFlashMarkerFrameZero || manualClapActive ? .black : .gray)
                    Text(clockBridge.isFlashMarkerFrameZero || manualClapActive ? "██ WHITE PEAK ██" : "WAIT :00")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(clockBridge.isFlashMarkerFrameZero || manualClapActive ? .black : .white)
                }
                .frame(width: 125, height: 52)
                .background(clockBridge.isFlashMarkerFrameZero || manualClapActive ? Color.white : Color(red: 0.08, green: 0.10, blue: 0.18))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.4), lineWidth: 1))

                // 10-Segment Sub-Frame Phase Comb + Continuous Sweep Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("SUB-FRAME SHUTTER PHASE BAR (0.0 -> 1.0)")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.1f%%", clockBridge.liveSubframePhase * 100.0))
                            .font(.system(size: 10.5, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.6))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [.cyan, .green, .yellow], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4.0, geo.size.width * CGFloat(clockBridge.liveSubframePhase)))
                        }
                    }
                    .frame(height: 16)

                    // 10 discrete 10% sub-frame tick blocks for DSLR shutter duration measurement
                    HStack(spacing: 3) {
                        ForEach(0..<10, id: \.self) { idx in
                            let active = Int(clockBridge.liveSubframePhase * 10.0) == idx
                            Text("\(idx)")
                                .font(.system(size: 10.5, weight: .black, design: .monospaced))
                                .foregroundColor(active ? .black : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                                .background(active ? Color.white : Color.white.opacity(0.06))
                                .cornerRadius(3)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(red: 0.05, green: 0.07, blue: 0.14))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.25), lineWidth: 1))
    }

    private var slateMetadataGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                slateField(title: "PRODUCTION", value: $clockBridge.slateProductionName)
                slateField(title: "SCENE", value: $clockBridge.slateScene)
                slateField(title: "CAM ROLL / SENSOR", value: $clockBridge.sensorId)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TAKE")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    HStack {
                        Button("-1") { clockBridge.slateTake = max(1, clockBridge.slateTake - 1) }
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan)
                        Spacer()
                        Text("\(clockBridge.slateTake)")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                        Spacer()
                        Button("+1") { clockBridge.slateTake += 1 }
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MASTER NODE IP")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    Text(clockBridge.discoveredMasterIP.isEmpty ? UDPStreamingManager.getLocalIPAddress() : clockBridge.discoveredMasterIP)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST BARRIER (50319)")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    Text(clockBridge.lastBarrierReceiptSummary)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(Color(red: 0.05, green: 0.07, blue: 0.14))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.25), lineWidth: 1))
    }

    private func slateField(title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            TextField(title, text: value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.black.opacity(0.4))
                .cornerRadius(6)
        }
        .frame(maxWidth: .infinity)
    }

    private func triggerManualOpticalClap() {
        manualClapActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.065) {
            manualClapActive = false
        }
    }
}
