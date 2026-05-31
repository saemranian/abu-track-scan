import SwiftUI

struct SettingsView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var streamManager = UDPStreamingManager.shared
    
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
                                    
                                    Slider(value: $captureRate, in: 10...60, step: 1)
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
                        
                        // Section 2.5: UDP Network Live Streaming
                        VStack(alignment: .leading, spacing: 12) {
                            Text("UDP Network Live Streaming")
                                .font(.caption)
                                .fontWeight(.black)
                                .foregroundColor(.cyan)
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Broadcast real-time positional and rotational tracker metrics directly to your Unreal Engine or FreeD device receiver.")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                
                                Toggle(isOn: $streamManager.isStreamingEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Enable UDP Broadcast")
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                        Text("Stream live tracking poses at \(String(format: "%.0f Hz", captureRate))")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .cyan))
                                
                                if streamManager.isStreamingEnabled {
                                    Divider()
                                        .background(Color.gray.opacity(0.3))
                                    
                                    HStack {
                                        Text("Mobile Device IP")
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                        Spacer()
                                        Text(UDPStreamingManager.getLocalIPAddress())
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                            .foregroundColor(.cyan)
                                    }
                                    .padding(.vertical, 4)
                                    
                                    Toggle(isOn: $streamManager.isBroadcastEnabled) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Subnet Broadcast Mode")
                                                .font(.footnote)
                                                .fontWeight(.bold)
                                            Text("Broadcasts to all devices (255.255.255.255)")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
                                    
                                    if !streamManager.isBroadcastEnabled {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Target IP Address(es)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.gray)
                                            
                                            TextField("e.g. 192.168.1.100 or 192.168.1.100, 192.168.1.101", text: $streamManager.streamIP)
                                                .font(.footnote)
                                                .padding(10)
                                                .background(Color(red: 0.08, green: 0.12, blue: 0.22))
                                                .cornerRadius(8)
                                                .foregroundColor(.white)
                                                .keyboardType(.numbersAndPunctuation)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                                .onSubmit {
                                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                                }
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Target IP Address")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.gray)
                                            Text("255.255.255.255 (Automatic Broadcast)")
                                                .font(.footnote)
                                                .foregroundColor(.cyan)
                                                .padding(10)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color(red: 0.08, green: 0.12, blue: 0.22))
                                                .cornerRadius(8)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Target Port")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.gray)
                                        
                                        TextField("e.g. 8080", text: Binding(
                                            get: { String(streamManager.streamPort) },
                                            set: { streamManager.streamPort = Int($0) ?? 8080 }
                                        ))
                                        .font(.footnote)
                                        .padding(10)
                                        .background(Color(red: 0.08, green: 0.12, blue: 0.22))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                        .keyboardType(.numberPad)
                                        .onSubmit {
                                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Streaming Protocol")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.gray)
                                        
                                        Picker("Protocol", selection: $streamManager.format) {
                                            ForEach(StreamingFormat.allCases) { fmt in
                                                Text(fmt.rawValue).tag(fmt)
                                            }
                                        }
                                        .pickerStyle(SegmentedPickerStyle())
                                        .padding(.top, 4)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(red: 0.05, green: 0.08, blue: 0.16))
                            .cornerRadius(14)
                            .padding(.horizontal)
                        }
                        
                        // Section 2.5: Coordinate Alignment Profile
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Coordinate System Alignment")
                                .font(.caption)
                                .fontWeight(.black)
                                .foregroundColor(.cyan)
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Align your iOS motion coordinate axes with your virtual production pipeline (e.g. Unreal Engine, Metashape).")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Pipeline Profile Preset")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.gray)
                                    
                                    Picker("Alignment Profile", selection: $streamManager.coordinatePreset) {
                                        Text("Default (ARKit)").tag("Default (ARKit)")
                                        Text("Unreal Engine").tag("Unreal Engine")
                                        Text("Metashape").tag("Metashape")
                                        Text("Custom").tag("Custom")
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                }
                                
                                if streamManager.coordinatePreset == "Custom" {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Custom Translation Axes Mapping")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.cyan)
                                            .padding(.top, 4)
                                        
                                        // X Mapping
                                        HStack {
                                            Text("Output X Axis:")
                                                .font(.footnote)
                                                .fontWeight(.bold)
                                            Spacer()
                                            Picker("X Sign", selection: $streamManager.xMapSign) {
                                                Text("+").tag(1.0)
                                                Text("-").tag(-1.0)
                                            }.pickerStyle(SegmentedPickerStyle()).frame(width: 80)
                                            Picker("X Source", selection: $streamManager.xMapSource) {
                                                Text("X").tag("X")
                                                Text("Y").tag("Y")
                                                Text("Z").tag("Z")
                                            }.pickerStyle(MenuPickerStyle()).frame(width: 85)
                                        }
                                        
                                        // Y Mapping
                                        HStack {
                                            Text("Output Y Axis:")
                                                .font(.footnote)
                                                .fontWeight(.bold)
                                            Spacer()
                                            Picker("Y Sign", selection: $streamManager.yMapSign) {
                                                Text("+").tag(1.0)
                                                Text("-").tag(-1.0)
                                            }.pickerStyle(SegmentedPickerStyle()).frame(width: 80)
                                            Picker("Y Source", selection: $streamManager.yMapSource) {
                                                Text("X").tag("X")
                                                Text("Y").tag("Y")
                                                Text("Z").tag("Z")
                                            }.pickerStyle(MenuPickerStyle()).frame(width: 85)
                                        }
                                        
                                        // Z Mapping
                                        HStack {
                                            Text("Output Z Axis:")
                                                .font(.footnote)
                                                .fontWeight(.bold)
                                            Spacer()
                                            Picker("Z Sign", selection: $streamManager.zMapSign) {
                                                Text("+").tag(1.0)
                                                Text("-").tag(-1.0)
                                            }.pickerStyle(SegmentedPickerStyle()).frame(width: 80)
                                            Picker("Z Source", selection: $streamManager.zMapSource) {
                                                Text("X").tag("X")
                                                Text("Y").tag("Y")
                                                Text("Z").tag("Z")
                                            }.pickerStyle(MenuPickerStyle()).frame(width: 85)
                                        }
                                        
                                        Divider().background(Color.gray.opacity(0.3))
                                        
                                        Text("Custom Rotation Axes Mapping")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.cyan)
                                        
                                        // Rotation Pitch Mapping
                                        HStack {
                                            Text("Output Pitch:")
                                                .font(.footnote)
                                                .fontWeight(.bold)
                                            Spacer()
                                            Picker("Pitch Sign", selection: $streamManager.pitchMapSign) {
                                                Text("+").tag(1.0)
                                                Text("-").tag(-1.0)
                                            }.pickerStyle(SegmentedPickerStyle()).frame(width: 80)
                                            Picker("Pitch Source", selection: $streamManager.pitchMapSource) {
                                                Text("Roll").tag("Roll")
                                                Text("Pitch").tag("Pitch")
                                                Text("Yaw").tag("Yaw")
                                            }.pickerStyle(MenuPickerStyle()).frame(width: 95)
                                        }
                                        
                                        // Rotation Yaw Mapping
                                        HStack {
                                            Text("Output Yaw:")
                                                .font(.footnote)
                                                .fontWeight(.bold)
                                            Spacer()
                                            Picker("Yaw Sign", selection: $streamManager.yawMapSign) {
                                                Text("+").tag(1.0)
                                                Text("-").tag(-1.0)
                                            }.pickerStyle(SegmentedPickerStyle()).frame(width: 80)
                                            Picker("Yaw Source", selection: $streamManager.yawMapSource) {
                                                Text("Roll").tag("Roll")
                                                Text("Pitch").tag("Pitch")
                                                Text("Yaw").tag("Yaw")
                                            }.pickerStyle(MenuPickerStyle()).frame(width: 95)
                                        }
                                        
                                        // Rotation Roll Mapping
                                        HStack {
                                            Text("Output Roll:")
                                                .font(.footnote)
                                                .fontWeight(.bold)
                                            Spacer()
                                            Picker("Roll Sign", selection: $streamManager.rollMapSign) {
                                                Text("+").tag(1.0)
                                                Text("-").tag(-1.0)
                                            }.pickerStyle(SegmentedPickerStyle()).frame(width: 80)
                                            Picker("Roll Source", selection: $streamManager.rollMapSource) {
                                                Text("Roll").tag("Roll")
                                                Text("Pitch").tag("Pitch")
                                                Text("Yaw").tag("Yaw")
                                            }.pickerStyle(MenuPickerStyle()).frame(width: 95)
                                        }
                                    }
                                    .padding(.top, 5)
                                }
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
                                DiagnosticRow(label: "Device Local IP", value: UDPStreamingManager.getLocalIPAddress())
                                DiagnosticRow(label: "LiDAR Hardware", value: "Available")
                                DiagnosticRow(label: "Barometer Sensor", value: "Supported")
                                DiagnosticRow(label: "RTK GNSS Provider", value: locationManager.horizontalAccuracy < 1.0 && locationManager.horizontalAccuracy > 0 ? "Bluetooth Sub-Centimeter (RTK)" : "iOS Native (Dual-Frequency)")
                            }
                            .padding()
                            .background(Color(red: 0.05, green: 0.08, blue: 0.16))
                            .cornerRadius(14)
                            .padding(.horizontal)
                        }
                        
                        // Section 4: About Abu Track
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About Abu Track")
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
                                        Text("Abu Track")
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
                                
                                DiagnosticRow(label: "App Version", value: VersionInfo.version)
                                DiagnosticRow(label: "Build Number", value: VersionInfo.build)
                                DiagnosticRow(label: "Compile Date", value: VersionInfo.buildTime)
                                DiagnosticRow(label: "Release State", value: "Active Development")
                            }
                            .padding()
                            .background(Color(red: 0.05, green: 0.08, blue: 0.16))
                            .cornerRadius(14)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                            
                            // Diagnostics & Troubleshooting Logs Card
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.cyan)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("PERSISTENT SYSTEM LOGS")
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                        Text("Enterprise-grade diagnostic logging")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                
                                Divider().background(Color.gray.opacity(0.3))
                                
                                Text("If you run into stream connectivity issues or raw hardware scan irregularities, export the persistent local log file for quick troubleshooting.")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 2)
                                
                                Button(action: {
                                    // Trigger sharing of the persistent log file
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let rootVC = windowScene.windows.first?.rootViewController {
                                        AppLogger.shared.shareLogFile(from: rootVC, sender: nil)
                                    }
                                }) {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "square.and.arrow.up")
                                        Text("EXPORT LOCAL APP LOGS")
                                            .fontWeight(.bold)
                                        Spacer()
                                    }
                                    .font(.caption)
                                    .padding()
                                    .foregroundColor(.black)
                                    .background(Color.cyan)
                                    .cornerRadius(10)
                                }
                            }
                            .padding()
                            .background(Color(red: 0.05, green: 0.08, blue: 0.16))
                            .cornerRadius(14)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle("RIG CALIBRATION")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .foregroundColor(.cyan)
                }
            }
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
