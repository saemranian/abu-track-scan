import SwiftUI

struct SettingsView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var trackingManager: MotionAndTrackingManager
    @ObservedObject var streamManager = UDPStreamingManager.shared
    
    @State private var leverArmX: String = ""
    @State private var leverArmY: String = ""
    @State private var leverArmZ: String = ""
    @State private var captureRate: Double = 10.0
    @State private var isGPSEnabled: Bool = true
    
    @State private var originOffsetX: String = ""
    @State private var originOffsetY: String = ""
    @State private var originOffsetZ: String = ""
    @State private var originOffsetYaw: String = ""
    
    @State private var lidarXSign: Double = 1.0
    @State private var lidarYSign: Double = 1.0
    @State private var lidarZSign: Double = 1.0
    @State private var lidarXSource: String = "X"
    @State private var lidarYSource: String = "Y"
    @State private var lidarZSource: String = "Z"
    
    @State private var selectedLens: String = "Wide"
    @State private var is4KEnabled: Bool = false
    @State private var videoCodec: String = "H.264"
    @State private var lensDistortionK1: Double = 0.0
    @State private var lensDistortionK2: Double = 0.0
    
    // Minimalist Segmented Navigation & Progressive Disclosure State
    @State private var settingsCategory: Int = 0 // 0 = Rig & Optics, 1 = Stream & Clock, 2 = Space & System
    @State private var showLidarAlignment: Bool = false
    @State private var showOriginOverrides: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                ProTheme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Segmented Category Bar (Eliminates 1,000-line scroll fatigue)
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(ProTheme.accentCyan)
                            Text("SYSTEM SETUP & CALIBRATION")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(ProTheme.textPrimary)
                            Spacer()
                            Text(VersionInfo.version)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ProTheme.accentCyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ProTheme.cardBackground)
                                .cornerRadius(6)
                        }
                        .padding(.horizontal, 16)

                        Picker("Setup Category", selection: $settingsCategory) {
                            Text("🎥 Rig & Optics").tag(0)
                            Text("📡 Stream & Clock").tag(1)
                            Text("⚙️ Space & System").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 10)
                    .background(Color(red: 0.03, green: 0.04, blue: 0.10))

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            if settingsCategory == 0 {
                                rigAndOpticsSection
                            } else if settingsCategory == 1 {
                                streamAndClockSection
                            } else {
                                spaceAndSystemSection
                            }
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }
            }
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationBarHidden(true)
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
            .onReceive(locationManager.$isGPSEnabled) { newValue in
                if self.isGPSEnabled != newValue {
                    self.isGPSEnabled = newValue
                }
            }
            .onChange(of: leverArmX) { _ in updateLeverArmX() }
            .onChange(of: leverArmY) { _ in updateLeverArmY() }
            .onChange(of: leverArmZ) { _ in updateLeverArmZ() }
            .onChange(of: originOffsetX) { _ in updateOriginOffsetX() }
            .onChange(of: originOffsetY) { _ in updateOriginOffsetY() }
            .onChange(of: originOffsetZ) { _ in updateOriginOffsetZ() }
            .onChange(of: originOffsetYaw) { _ in updateOriginOffsetYaw() }
            .onChange(of: lidarXSign) { _ in updateLidarXSign() }
            .onChange(of: lidarYSign) { _ in updateLidarYSign() }
            .onChange(of: lidarZSign) { _ in updateLidarZSign() }
            .onChange(of: lidarXSource) { _ in updateLidarXSource() }
            .onChange(of: lidarYSource) { _ in updateLidarYSource() }
            .onChange(of: lidarZSource) { _ in updateLidarZSource() }
            .onChange(of: selectedLens) { newValue in
                RigSettings.selectedLens = newValue
                trackingManager.updateCameraConfiguration()
                
                // Automatically load model-specific defaults for lens distortion
                let defaults = trackingManager.getDefaultDistortion(for: newValue)
                RigSettings.lensDistortionK1 = defaults.0
                RigSettings.lensDistortionK2 = defaults.1
                self.lensDistortionK1 = defaults.0
                self.lensDistortionK2 = defaults.1
            }
            .onChange(of: is4KEnabled) { newValue in
                RigSettings.is4KEnabled = newValue
                trackingManager.updateCameraConfiguration()
            }
            .onChange(of: videoCodec) { newValue in
                RigSettings.videoCodec = newValue
            }
            .onChange(of: lensDistortionK1) { newValue in
                RigSettings.lensDistortionK1 = newValue
            }
            .onChange(of: lensDistortionK2) { newValue in
                RigSettings.lensDistortionK2 = newValue
            }
        }
    }

    private func sectionHeader(icon: String, title: String, topic: HelpTopic?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(ProTheme.accentCyan)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(ProTheme.textPrimary)
            Spacer()
            if let topic = topic {
                InfoHelpButton(topic: topic)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Tab 0: Rig & Optics

    private var rigAndOpticsSection: some View {
        VStack(spacing: 16) {
            // Card 1: Logging & Sampling
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "waveform.path.ecg", title: "Sampling & Geolocation", topic: .loggingParams)

                VStack(spacing: 12) {
                    Toggle(isOn: $isGPSEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Absolute GNSS / GPS Georeferencing")
                                .font(.footnote)
                                .fontWeight(.bold)
                            Text("Disable indoors to prevent multipath GPS drift")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .onChange(of: isGPSEnabled) { newValue in
                        RigSettings.isGPSEnabled = newValue
                        locationManager.isGPSEnabled = newValue
                    }
                    .tint(ProTheme.statusNominal)

                    Divider().background(ProTheme.borderSubtle)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Telemetry Capture Rate")
                                .font(.footnote)
                                .fontWeight(.bold)
                            Spacer()
                            Text(String(format: "%.0f Hz", captureRate))
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundColor(ProTheme.accentCyan)
                        }

                        Slider(value: $captureRate, in: 10...60, step: 1)
                            .tint(ProTheme.accentCyan)
                            .onChange(of: captureRate) { newValue in
                                RigSettings.captureRate = newValue
                            }

                        HStack(spacing: 8) {
                            ForEach([15.0, 24.0, 30.0, 60.0], id: \.self) { presetHz in
                                Button(action: {
                                    captureRate = presetHz
                                    RigSettings.captureRate = presetHz
                                }) {
                                    Text("\(Int(presetHz)) Hz")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(captureRate == presetHz ? .black : .white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(captureRate == presetHz ? ProTheme.accentCyan : Color.white.opacity(0.08))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(ProTheme.cardBackground)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
                .padding(.horizontal)
            }

            // Card 2: DSLR / Mirrorless Lever-Arm Offsets
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "ruler.fill", title: "DSLR / Cinema Rig Lever-Arm (cm)", topic: .dslrRigOffsets)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Physical distance from the iPhone Rear Main (1x) lens to your external camera's sensor plane mark (⌀). Leave at 0, 0, 0 for Single-Device mode. Outgoing UDP packets tag leverArmApplied=true to prevent double-compensation on PC/UE5.")
                        .font(.caption2)
                        .foregroundColor(ProTheme.textSecondary)

                    HStack(spacing: 10) {
                        OffsetInputField(label: "Right (+X)", value: $leverArmX, placeholder: "0.0") { saveOffsets() }
                        OffsetInputField(label: "Up (+Y)", value: $leverArmY, placeholder: "+5.0") { saveOffsets() }
                        OffsetInputField(label: "Forward (-Z)", value: $leverArmZ, placeholder: "+12.0") { saveOffsets() }
                    }
                }
                .padding(14)
                .background(ProTheme.cardBackground)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
                .padding(.horizontal)
            }

            // Card 3: Camera Lens & Distortion Calibration
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "camera.aperture", title: "Camera Lens & Optical Distortion", topic: .cameraOptics)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active Optical Lens")
                            .font(.footnote)
                            .fontWeight(.bold)
                        Picker("Lens", selection: $selectedLens) {
                            Text("Wide (1x)").tag("Wide")
                            Text("Ultra Wide").tag("UltraWide")
                            Text("Telephoto").tag("Telephoto")
                            Text("Front (180°)").tag("Front")
                        }
                        .pickerStyle(.segmented)
                        Text("Factory nodal offsets & 180° Front TrueDepth rotation are applied automatically.")
                            .font(.caption2)
                            .foregroundColor(ProTheme.textSecondary)
                    }

                    Divider().background(ProTheme.borderSubtle)

                    Toggle(isOn: $is4KEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("4K UHD Video Capture (3840×2160)")
                                .font(.footnote)
                                .fontWeight(.bold)
                            Text("Hardware-encoded RTP stream with RFC 5285 timecode")
                                .font(.caption2)
                                .foregroundColor(ProTheme.textSecondary)
                        }
                    }
                    .tint(ProTheme.accentCyan)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hardware Video Encoder")
                            .font(.footnote)
                            .fontWeight(.bold)
                        Picker("Codec", selection: $videoCodec) {
                            Text("H.264 (Universal)").tag("H.264")
                            Text("H.265 / HEVC (50% Smaller)").tag("H.265")
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().background(ProTheme.borderSubtle)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Radial Distortion K1 / K2")
                                .font(.footnote)
                                .fontWeight(.bold)
                            Spacer()
                            Text(String(format: "K1: %+.3f  K2: %+.3f", lensDistortionK1, lensDistortionK2))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(ProTheme.accentCyan)
                        }
                        Slider(value: $lensDistortionK1, in: -0.5...0.5, step: 0.001)
                            .tint(ProTheme.accentCyan)
                        Slider(value: $lensDistortionK2, in: -0.5...0.5, step: 0.001)
                            .tint(ProTheme.accentCyan)
                    }
                }
                .padding(14)
                .background(ProTheme.cardBackground)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Tab 1: Stream & Clock

    private var streamAndClockSection: some View {
        VStack(spacing: 16) {
            // Card 1: UDP LiveLink / FreeD-TC / OpenTrackIO Streaming
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "antenna.radiowaves.left.and.right", title: "Live Telemetry & 4K RTP Stream", topic: .udpLiveStream)

                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $streamManager.isStreamingEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Enable Live Telemetry Stream")
                                .font(.footnote)
                                .fontWeight(.bold)
                            Text("Streams 6-DOF pose + SMPTE ST 2059-2 timecode at \(Int(captureRate)) Hz")
                                .font(.caption2)
                                .foregroundColor(ProTheme.textSecondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: ProTheme.accentCyan))

                    if streamManager.isStreamingEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Wire Protocol")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(ProTheme.textSecondary)

                            Picker("Protocol", selection: $streamManager.format) {
                                ForEach(StreamingFormat.allCases) { fmt in
                                    Text(fmt.rawValue).tag(fmt)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Toggle(isOn: $streamManager.isBroadcastEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("LAN Subnet Broadcast (255.255.255.255)")
                                    .font(.footnote)
                                    .fontWeight(.bold)
                                Text("Disable to target specific PC / UE5 IP addresses")
                                    .font(.caption2)
                                    .foregroundColor(ProTheme.textSecondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: ProTheme.accentCyan))

                        HStack(spacing: 10) {
                            if !streamManager.isBroadcastEnabled {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Target IP")
                                        .font(.caption2)
                                        .foregroundColor(ProTheme.textSecondary)
                                    TextField("192.168.1.100", text: $streamManager.streamIP)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .padding(9)
                                        .background(ProTheme.surfaceElevated)
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                        .keyboardType(.numbersAndPunctuation)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("UDP Port")
                                    .font(.caption2)
                                    .foregroundColor(ProTheme.textSecondary)
                                TextField("8080", text: Binding(
                                    get: { String(streamManager.streamPort) },
                                    set: { streamManager.streamPort = Int($0) ?? 8080 }
                                ))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .padding(9)
                                .frame(width: 90)
                                .background(ProTheme.surfaceElevated)
                                .cornerRadius(8)
                                .foregroundColor(ProTheme.accentCyan)
                                .keyboardType(.numberPad)
                            }
                        }
                    }

                    Divider().background(ProTheme.borderSubtle)

                    Toggle(isOn: $trackingManager.isLiveVideoStreamingEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Stream RTP Video to PC / UE5")
                                .font(.footnote)
                                .fontWeight(.bold)
                            Text("Carries RFC 5285 (0xBEDE) BCD Timecode & TAI Nanoseconds")
                                .font(.caption2)
                                .foregroundColor(ProTheme.textSecondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: ProTheme.statusCritical))

                    if trackingManager.isLiveVideoStreamingEnabled {
                        HStack {
                            Text("RTP Video Port")
                                .font(.footnote)
                                .fontWeight(.bold)
                            Spacer()
                            TextField("5004", value: $trackingManager.videoStreamPort, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(ProTheme.accentCyan)
                                .frame(width: 80)
                        }

                        Picker("Quality", selection: $trackingManager.videoStreamQuality) {
                            Text("Low").tag("Low (480p @ 800Kbps)")
                            Text("Med").tag("Medium (540p @ 1.5Mbps)")
                            Text("High").tag("High (720p @ 3.0Mbps)")
                            Text("1080p").tag("Cinematic (1080p @ 8.0Mbps)")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(14)
                .background(ProTheme.cardBackground)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
                .padding(.horizontal)
            }

            // Card 2: Abu Clock Master Synchronization
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "clock.badge.checkmark.fill", title: "Abu Clock & SMPTE Timecode", topic: .abuClockHud)

                VStack(alignment: .leading, spacing: 12) {
                    DiagnosticRow(label: "Live SMPTE Timecode", value: AbuClockKitBridge.shared.liveSmpteTimecode)
                    DiagnosticRow(label: "32-Bit BCD Word", value: AbuClockKitBridge.shared.liveBcdHex)
                    DiagnosticRow(label: "Kalman PLL Status", value: AbuClockKitBridge.shared.lockState)
                    DiagnosticRow(label: "Local Device IP", value: UDPStreamingManager.getLocalIPAddress())

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        AbuClockKitBridge.shared.discoverAbuClockMaster(completion: nil)
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text("RE-DISCOVER ABU CLOCK MASTER (UDP 50320)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .foregroundColor(.black)
                        .background(ProTheme.accentCyan)
                        .cornerRadius(8)
                    }
                }
                .padding(14)
                .background(ProTheme.cardBackground)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Tab 2: Space & System

    private var spaceAndSystemSection: some View {
        VStack(spacing: 16) {
            // Card 1: Coordinate System Preset + Auto-Collapsed Custom Remapping
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "move.3d", title: "Coordinate System & Axis Alignment", topic: .coordinateSpace)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Select your target 3D pipeline preset. Custom axis remapping opens automatically only when 'Custom' is selected.")
                        .font(.caption2)
                        .foregroundColor(ProTheme.textSecondary)

                    Picker("Alignment Profile", selection: $streamManager.coordinatePreset) {
                        Text("ARKit").tag("Default (ARKit)")
                        Text("Unreal").tag("Unreal Engine")
                        Text("Metashape").tag("Metashape")
                        Text("Custom").tag("Custom")
                    }
                    .pickerStyle(.segmented)

                    if streamManager.coordinatePreset == "Custom" {
                        Divider().background(ProTheme.borderSubtle)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Custom Pose Axis Remapping")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(ProTheme.accentCyan)

                            HStack {
                                Text("Output X:").font(.footnote).fontWeight(.bold)
                                Spacer()
                                Picker("X Sign", selection: $streamManager.xMapSign) {
                                    Text("+").tag(1.0); Text("-").tag(-1.0)
                                }.pickerStyle(.segmented).frame(width: 75)
                                Picker("X Source", selection: $streamManager.xMapSource) {
                                    Text("X").tag("X"); Text("Y").tag("Y"); Text("Z").tag("Z")
                                }.pickerStyle(.menu).frame(width: 80)
                            }
                            HStack {
                                Text("Output Y:").font(.footnote).fontWeight(.bold)
                                Spacer()
                                Picker("Y Sign", selection: $streamManager.yMapSign) {
                                    Text("+").tag(1.0); Text("-").tag(-1.0)
                                }.pickerStyle(.segmented).frame(width: 75)
                                Picker("Y Source", selection: $streamManager.yMapSource) {
                                    Text("X").tag("X"); Text("Y").tag("Y"); Text("Z").tag("Z")
                                }.pickerStyle(.menu).frame(width: 80)
                            }
                            HStack {
                                Text("Output Z:").font(.footnote).fontWeight(.bold)
                                Spacer()
                                Picker("Z Sign", selection: $streamManager.zMapSign) {
                                    Text("+").tag(1.0); Text("-").tag(-1.0)
                                }.pickerStyle(.segmented).frame(width: 75)
                                Picker("Z Source", selection: $streamManager.zMapSource) {
                                    Text("X").tag("X"); Text("Y").tag("Y"); Text("Z").tag("Z")
                                }.pickerStyle(.menu).frame(width: 80)
                            }
                            HStack {
                                Text("Output Pitch:").font(.footnote).fontWeight(.bold)
                                Spacer()
                                Picker("Pitch Sign", selection: $streamManager.pitchMapSign) {
                                    Text("+").tag(1.0); Text("-").tag(-1.0)
                                }.pickerStyle(.segmented).frame(width: 75)
                                Picker("Pitch Source", selection: $streamManager.pitchMapSource) {
                                    Text("Roll").tag("Roll"); Text("Pitch").tag("Pitch"); Text("Yaw").tag("Yaw")
                                }.pickerStyle(.menu).frame(width: 90)
                            }
                            HStack {
                                Text("Output Yaw:").font(.footnote).fontWeight(.bold)
                                Spacer()
                                Picker("Yaw Sign", selection: $streamManager.yawMapSign) {
                                    Text("+").tag(1.0); Text("-").tag(-1.0)
                                }.pickerStyle(.segmented).frame(width: 75)
                                Picker("Yaw Source", selection: $streamManager.yawMapSource) {
                                    Text("Roll").tag("Roll"); Text("Pitch").tag("Pitch"); Text("Yaw").tag("Yaw")
                                }.pickerStyle(.menu).frame(width: 90)
                            }
                            HStack {
                                Text("Output Roll:").font(.footnote).fontWeight(.bold)
                                Spacer()
                                Picker("Roll Sign", selection: $streamManager.rollMapSign) {
                                    Text("+").tag(1.0); Text("-").tag(-1.0)
                                }.pickerStyle(.segmented).frame(width: 75)
                                Picker("Roll Source", selection: $streamManager.rollMapSource) {
                                    Text("Roll").tag("Roll"); Text("Pitch").tag("Pitch"); Text("Yaw").tag("Yaw")
                                }.pickerStyle(.menu).frame(width: 90)
                            }
                        }
                    }

                    Divider().background(ProTheme.borderSubtle)

                    // Collapsible LiDAR Point Cloud Axis Remap
                    DisclosureGroup("Advanced LiDAR Point Cloud Axis Remap", isExpanded: $showLidarAlignment) {
                        VStack(spacing: 10) {
                            HStack {
                                Text("LiDAR X:").font(.footnote).fontWeight(.bold)
                                Spacer()
                                Picker("X Sign", selection: $lidarXSign) {
                                    Text("+").tag(1.0); Text("-").tag(-1.0)
                                }.pickerStyle(.segmented).frame(width: 75)
                                Picker("X Source", selection: $lidarXSource) {
                                    Text("X").tag("X"); Text("Y").tag("Y"); Text("Z").tag("Z")
                                }.pickerStyle(.menu).frame(width: 80)
                            }
                            HStack {
                                Text("LiDAR Y:").font(.footnote).fontWeight(.bold)
                                Spacer()
                                Picker("Y Sign", selection: $lidarYSign) {
                                    Text("+").tag(1.0); Text("-").tag(-1.0)
                                }.pickerStyle(.segmented).frame(width: 75)
                                Picker("Y Source", selection: $lidarYSource) {
                                    Text("X").tag("X"); Text("Y").tag("Y"); Text("Z").tag("Z")
                                }.pickerStyle(.menu).frame(width: 80)
                            }
                            HStack {
                                Text("LiDAR Z:").font(.footnote).fontWeight(.bold)
                                Spacer()
                                Picker("Z Sign", selection: $lidarZSign) {
                                    Text("+").tag(1.0); Text("-").tag(-1.0)
                                }.pickerStyle(.segmented).frame(width: 75)
                                Picker("Z Source", selection: $lidarZSource) {
                                    Text("X").tag("X"); Text("Y").tag("Y"); Text("Z").tag("Z")
                                }.pickerStyle(.menu).frame(width: 80)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ProTheme.textPrimary)
                    .tint(ProTheme.accentCyan)
                }
                .padding(14)
                .background(ProTheme.cardBackground)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
                .padding(.horizontal)
            }

            // Card 2: Collapsible World Origin (0,0,0) Overrides
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "scope", title: "Stage World Origin Overrides", topic: .originOverrides)

                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup("Configure Stage Survey Origin (X, Y, Z, Yaw)", isExpanded: $showOriginOverrides) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                OffsetInputFieldMeters(label: "Origin X", value: $originOffsetX, placeholder: "0.0") { saveOffsets() }
                                OffsetInputFieldMeters(label: "Origin Y", value: $originOffsetY, placeholder: "0.0") { saveOffsets() }
                                OffsetInputFieldMeters(label: "Origin Z", value: $originOffsetZ, placeholder: "0.0") { saveOffsets() }
                            }
                            HStack {
                                Text("Origin Yaw Offset (°)")
                                    .font(.caption2)
                                    .foregroundColor(ProTheme.textSecondary)
                                Spacer()
                                TextField("0.0", text: $originOffsetYaw, onCommit: { saveOffsets() })
                                    .font(.caption)
                                    .keyboardType(.numbersAndPunctuation)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                    .padding(8)
                                    .background(Color.black.opacity(0.4))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ProTheme.textPrimary)
                    .tint(ProTheme.accentCyan)
                }
                .padding(14)
                .background(ProTheme.cardBackground)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
                .padding(.horizontal)
            }

            // Card 3: About, Version & Log Export
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "info.circle.fill", title: "About Abu Track & Scan", topic: nil)

                VStack(alignment: .leading, spacing: 10) {
                    DiagnosticRow(label: "iOS App Version", value: "\(VersionInfo.version) (Build #\(VersionInfo.build))")
                    DiagnosticRow(label: "Compiled Timestamp", value: VersionInfo.buildTime)
                    DiagnosticRow(label: "Local IPv4 Address", value: UDPStreamingManager.getLocalIPAddress())
                    DiagnosticRow(label: "GNSS Provider", value: locationManager.horizontalAccuracy < 1.0 && locationManager.horizontalAccuracy > 0 ? "RTK Sub-cm" : "Dual-Freq GPS")

                    Button(action: {
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootVC = windowScene.windows.first?.rootViewController {
                            AppLogger.shared.shareLogFile(from: rootVC, sender: nil)
                        }
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                            Text("EXPORT DIAGNOSTIC LOGS")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .foregroundColor(.black)
                        .background(ProTheme.accentCyan)
                        .cornerRadius(8)
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .background(ProTheme.cardBackground)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ProTheme.borderSubtle, lineWidth: 1))
                .padding(.horizontal)
            }
        }
    }
    
    private func loadOffsets() {
        self.isGPSEnabled = RigSettings.isGPSEnabled
        self.captureRate = RigSettings.captureRate
        
        let x = RigSettings.leverArmX
        let y = RigSettings.leverArmY
        let z = RigSettings.leverArmZ
        
        let ox = RigSettings.originOffsetX
        let oy = RigSettings.originOffsetY
        let oz = RigSettings.originOffsetZ
        let oyaw = RigSettings.originOffsetYaw
        
        self.leverArmX = x == 0 ? "" : String(format: "%.1f", x)
        self.leverArmY = y == 0 ? "" : String(format: "%.1f", y)
        self.leverArmZ = z == 0 ? "" : String(format: "%.1f", z)
        
        self.originOffsetX = ox == 0 ? "" : String(format: "%.2f", ox)
        self.originOffsetY = oy == 0 ? "" : String(format: "%.2f", oy)
        self.originOffsetZ = oz == 0 ? "" : String(format: "%.2f", oz)
        self.originOffsetYaw = oyaw == 0 ? "" : String(format: "%.1f", oyaw)
        
        self.lidarXSign = RigSettings.lidarXSign
        self.lidarYSign = RigSettings.lidarYSign
        self.lidarZSign = RigSettings.lidarZSign
        self.lidarXSource = RigSettings.lidarXSource
        self.lidarYSource = RigSettings.lidarYSource
        self.lidarZSource = RigSettings.lidarZSource
        
        self.selectedLens = RigSettings.selectedLens
        self.is4KEnabled = RigSettings.is4KEnabled
        self.videoCodec = RigSettings.videoCodec
        self.lensDistortionK1 = RigSettings.lensDistortionK1
        self.lensDistortionK2 = RigSettings.lensDistortionK2
    }
    
    private func saveOffsets() {
        let x = Double(leverArmX) ?? 0.0
        let y = Double(leverArmY) ?? 0.0
        let z = Double(leverArmZ) ?? 0.0
        
        let ox = Double(originOffsetX) ?? 0.0
        let oy = Double(originOffsetY) ?? 0.0
        let oz = Double(originOffsetZ) ?? 0.0
        let oyaw = Double(originOffsetYaw) ?? 0.0
        
        RigSettings.leverArmX = x
        RigSettings.leverArmY = y
        RigSettings.leverArmZ = z
        
        RigSettings.originOffsetX = ox
        RigSettings.originOffsetY = oy
        RigSettings.originOffsetZ = oz
        RigSettings.originOffsetYaw = oyaw
    }
    
    private func updateLeverArmX() { RigSettings.leverArmX = Double(leverArmX) ?? 0.0 }
    private func updateLeverArmY() { RigSettings.leverArmY = Double(leverArmY) ?? 0.0 }
    private func updateLeverArmZ() { RigSettings.leverArmZ = Double(leverArmZ) ?? 0.0 }
    private func updateOriginOffsetX() { RigSettings.originOffsetX = Double(originOffsetX) ?? 0.0 }
    private func updateOriginOffsetY() { RigSettings.originOffsetY = Double(originOffsetY) ?? 0.0 }
    private func updateOriginOffsetZ() { RigSettings.originOffsetZ = Double(originOffsetZ) ?? 0.0 }
    private func updateOriginOffsetYaw() { RigSettings.originOffsetYaw = Double(originOffsetYaw) ?? 0.0 }
    
    private func updateLidarXSign() { RigSettings.lidarXSign = lidarXSign }
    private func updateLidarYSign() { RigSettings.lidarYSign = lidarYSign }
    private func updateLidarZSign() { RigSettings.lidarZSign = lidarZSign }
    private func updateLidarXSource() { RigSettings.lidarXSource = lidarXSource }
    private func updateLidarYSource() { RigSettings.lidarYSource = lidarYSource }
    private func updateLidarZSource() { RigSettings.lidarZSource = lidarZSource }
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

struct OffsetInputFieldMeters: View {
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
                    .keyboardType(.numbersAndPunctuation)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("m")
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
