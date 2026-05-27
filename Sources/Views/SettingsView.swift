import SwiftUI

struct SettingsView: View {
    @ObservedObject var locationManager: LocationManager
    
    @State private var leverArmX: String = ""
    @State private var leverArmY: String = ""
    @State private var leverArmZ: String = ""
    @State private var captureRate: Double = 10.0
    @State private var isGPSEnabled: Bool = true
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.02, green: 0.03, blue: 0.08)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // Section 1: Core System Logs Settings
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Logging Parameters")
                                .font(.caption)
                                .fontWeight(.black)
                                .foregroundColor(.cyan)
                                .padding(.horizontal)
                                .padding(.top, 10)
                            
                            VStack(spacing: 12) {
                                Toggle(isOn: $isGPSEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Enable Absolute GPS")
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                        Text("Toggle off for indoor drift avoidance")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .onChange(of: isGPSEnabled) { newValue in
                                    RigSettings.isGPSEnabled = newValue
                                    locationManager.isGPSEnabled = newValue
                                }
                                .tint(.green)
                                
                                Divider().background(Color.gray.opacity(0.3))
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("IMU Sampling Rate")
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                        Spacer()
                                        Text(String(format: "%.0f Hz", captureRate))
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                            .foregroundColor(.cyan)
                                    }
                                    
                                    Slider(value: $captureRate, in: 10...60, step: 10)
                                        .tint(.cyan)
                                        .onChange(of: captureRate) { newValue in
                                            RigSettings.captureRate = newValue
                                        }
                                    
                                    Text("Higher frequencies capture rapid shifts but consume more storage.")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding()
                            .background(Color(red: 0.05, green: 0.08, blue: 0.16))
                            .cornerRadius(14)
                            .padding(.horizontal)
                        }
                        
                        // Section 2: Pro DSLR / Mirrorless Hot-Shoe Mode Offset
                        VStack(alignment: .leading, spacing: 12) {
                            Text("DSLR/Mirrorless Rig Calibration")
                                .font(.caption)
                                .fontWeight(.black)
                                .foregroundColor(.cyan)
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Set the physical offset between the center of your iPhone's camera sensor and your DSLR's optical CMOS sensor.")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                
                                HStack(spacing: 12) {
                                    // X Offset
                                    OffsetInputField(label: "X Offset (Left/Right)", value: $leverArmX, placeholder: "0.0") {
                                        saveOffsets()
                                    }
                                    
                                    // Y Offset
                                    OffsetInputField(label: "Y Offset (Up/Down)", value: $leverArmY, placeholder: "+5.0") {
                                        saveOffsets()
                                    }
                                    
                                    // Z Offset
                                    OffsetInputField(label: "Z Offset (Depth)", value: $leverArmZ, placeholder: "+12.0") {
                                        saveOffsets()
                                    }
                                }
                                
                                // Mini Graphical Guide
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.cyan)
                                        Text("Measuring Your Rig Guide")
                                            .font(.caption2)
                                            .fontWeight(.black)
                                    }
                                    .padding(.top, 5)
                                    
                                    Text("• X: Positive if phone is offset to the right of lens axis.\n• Y: Positive if phone is mounted higher than lens center.\n• Z: Positive if phone is mounted further forward than DSLR sensor plane.\n• Set to 0.0, 0.0, 0.0 if using the default iPhone camera.")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                        .lineSpacing(4)
                                }
                                .padding(.top, 5)
                            }
                            .padding()
                            .background(Color(red: 0.05, green: 0.08, blue: 0.16))
                            .cornerRadius(14)
                            .padding(.horizontal)
                        }
                        
                        // Section 3: Hardware Diagnostics info
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Platform Diagnostics")
                                .font(.caption)
                                .fontWeight(.black)
                                .foregroundColor(.cyan)
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                DiagnosticRow(label: "Device Model", value: "iPhone 16 Pro Max")
                                DiagnosticRow(label: "LiDAR Hardware", value: "Available")
                                DiagnosticRow(label: "Barometer Sensor", value: "Supported")
                                DiagnosticRow(label: "RTK GNSS Provider", value: locationManager.horizontalAccuracy < 1.0 && locationManager.horizontalAccuracy > 0 ? "Bluetooth Sub-Centimeter (RTK)" : "iOS Native (Dual-Frequency)")
                            }
                            .padding()
                            .background(Color(red: 0.05, green: 0.08, blue: 0.16))
                            .cornerRadius(14)
                            .padding(.horizontal)
                        }
                        
                        // Section 4: About CamTrack Pro
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About CamTrack Pro")
                                .font(.caption)
                                .fontWeight(.black)
                                .foregroundColor(.cyan)
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.cyan)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("CamTrack Pro")
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                        Text("Industrial Reality Capture Sync Engine")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                .padding(.bottom, 4)
                                
                                Divider().background(Color.gray.opacity(0.3))
                                
                                DiagnosticRow(label: "App Version", value: "0.0.3")
                                DiagnosticRow(label: "Build Try", value: "15")
                                DiagnosticRow(label: "Compile Date", value: "2026-05-27 11:50")
                                DiagnosticRow(label: "Release State", value: "Active Development")
                            }
                            .padding()
                            .background(Color(red: 0.05, green: 0.08, blue: 0.16))
                            .cornerRadius(14)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("RIG CALIBRATION")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadOffsets()
            }
        }
    }
    
    private func loadOffsets() {
        self.isGPSEnabled = RigSettings.isGPSEnabled
        self.captureRate = RigSettings.captureRate
        
        let x = RigSettings.leverArmX
        let y = RigSettings.leverArmY
        let z = RigSettings.leverArmZ
        
        self.leverArmX = x == 0 ? "" : String(format: "%.1f", x)
        self.leverArmY = y == 0 ? "" : String(format: "%.1f", y)
        self.leverArmZ = z == 0 ? "" : String(format: "%.1f", z)
    }
    
    private func saveOffsets() {
        let x = Double(leverArmX) ?? 0.0
        let y = Double(leverArmY) ?? 0.0
        let z = Double(leverArmZ) ?? 0.0
        
        RigSettings.leverArmX = x
        RigSettings.leverArmY = y
        RigSettings.leverArmZ = z
    }
}

struct OffsetInputField: View {
    let label: String
    @Binding var value: String
    let placeholder: String
    let onCommit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            
            HStack {
                TextField(placeholder, text: $value, onCommit: onCommit)
                    .font(.caption)
                    .keyboardType(.decimalPad)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("cm")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(10)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.cyan)
        }
    }
}
