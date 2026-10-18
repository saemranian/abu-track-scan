import SwiftUI

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var trackingManager = MotionAndTrackingManager()
    @ObservedObject private var clockBridge = AbuClockKitBridge.shared
    
    @State private var selectedTab = 0
    @State private var requestedPermissions = false
    @State private var showDigitalSlate = false
    @State private var showQuickGuide = false
    
    init() {
        // Customize tab bar colors for premium dark theme
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
        
        let activeColor = UIColor(red: 0.0, green: 0.85, blue: 0.9, alpha: 1.0)
        let inactiveColor = UIColor.gray
        
        appearance.stackedLayoutAppearance.selected.iconColor = activeColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: activeColor]
        appearance.stackedLayoutAppearance.normal.iconColor = inactiveColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: inactiveColor]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Minimalist Abu Clock SMPTE ST 12-1 / ST 2059-2 Timecode & Quick-Action Top Bar
            HStack(spacing: 8) {
                // Unified Abu Studio Green 'A' App Icon Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 0.204, green: 0.827, blue: 0.600))
                        .frame(width: 24, height: 24)
                    Text("A")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.067, green: 0.094, blue: 0.153))
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(clockBridge.lockState.contains("Locked") ? ProTheme.statusNominal : ProTheme.statusWarning)
                        .frame(width: 7, height: 7)
                    Text(clockBridge.liveSmpteTimecode)
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(clockBridge.isFlashMarkerFrameZero ? .yellow : .white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ProTheme.cardBackground)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))

                Text(clockBridge.lockState)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(ProTheme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                InfoHelpButton(topic: .abuClockHud)

                Button(action: {
                    showDigitalSlate = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "film.stack")
                        Text("SLATE")
                    }
                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ProTheme.accentCyan)
                    .cornerRadius(6)
                }

                Button(action: {
                    showQuickGuide = true
                }) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ProTheme.accentCyan)
                        .frame(width: 28, height: 28)
                        .background(ProTheme.accentCyan.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.03, green: 0.05, blue: 0.12))

            TabView(selection: $selectedTab) {
                DashboardView(locationManager: locationManager, trackingManager: trackingManager)
                    .tabItem {
                        Image(systemName: "scope")
                        Text("Track & Scan")
                    }
                    .tag(0)
                
                SessionsView()
                    .tabItem {
                        Image(systemName: "folder.fill")
                        Text("Sessions")
                    }
                    .tag(1)
                
                SettingsView(locationManager: locationManager, trackingManager: trackingManager)
                    .tabItem {
                        Image(systemName: "slider.horizontal.3")
                        Text("Setup")
                    }
                    .tag(2)
                
                UEMonitorView()
                    .tabItem {
                        Image(systemName: "tv.and.mediabox.fill")
                        Text("Monitor")
                    }
                    .tag(3)
                
                AcademyView()
                    .tabItem {
                        Image(systemName: "book.fill")
                        Text("Guide")
                    }
                    .tag(4)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showDigitalSlate) {
            AbuClockSlateView()
        }
        .sheet(isPresented: $showQuickGuide) {
            QuickStartGuideSheet()
        }
        .onAppear {
            if !requestedPermissions {
                locationManager.requestPermissions()
                requestedPermissions = true
            }
            AbuClockKitBridge.shared.discoverAbuClockMaster(completion: nil)
        }
    }
}

// Global struct to store DSLR calibration variables in UserDefaults
struct RigSettings {
    static var leverArmX: Double {
        get { UserDefaults.standard.double(forKey: "leverArmX") }
        set { UserDefaults.standard.set(newValue, forKey: "leverArmX") }
    }
    static var leverArmY: Double {
        get { UserDefaults.standard.double(forKey: "leverArmY") }
        set { UserDefaults.standard.set(newValue, forKey: "leverArmY") }
    }
    static var leverArmZ: Double {
        get { UserDefaults.standard.double(forKey: "leverArmZ") }
        set { UserDefaults.standard.set(newValue, forKey: "leverArmZ") }
    }
    static var originOffsetX: Double {
        get { UserDefaults.standard.double(forKey: "originOffsetX") }
        set { UserDefaults.standard.set(newValue, forKey: "originOffsetX") }
    }
    static var originOffsetY: Double {
        get { UserDefaults.standard.double(forKey: "originOffsetY") }
        set { UserDefaults.standard.set(newValue, forKey: "originOffsetY") }
    }
    static var originOffsetZ: Double {
        get { UserDefaults.standard.double(forKey: "originOffsetZ") }
        set { UserDefaults.standard.set(newValue, forKey: "originOffsetZ") }
    }
    static var originOffsetYaw: Double {
        get { UserDefaults.standard.double(forKey: "originOffsetYaw") }
        set { UserDefaults.standard.set(newValue, forKey: "originOffsetYaw") }
    }
    static var captureRate: Double {
        get { 
            let rate = UserDefaults.standard.double(forKey: "captureRate")
            return rate == 0 ? 10.0 : rate
        }
        set { UserDefaults.standard.set(newValue, forKey: "captureRate") }
    }
    static var isGPSEnabled: Bool {
        get { 
            if UserDefaults.standard.object(forKey: "isGpsEnabled") != nil {
                return UserDefaults.standard.bool(forKey: "isGpsEnabled")
            }
            if UserDefaults.standard.object(forKey: "isGPSEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "isGPSEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isGPSEnabled")
            UserDefaults.standard.set(newValue, forKey: "isGpsEnabled")
        }
    }
    static var lidarXSign: Double {
        get { 
            let val = UserDefaults.standard.double(forKey: "lidarXSign")
            return val == 0 ? 1.0 : val
        }
        set { UserDefaults.standard.set(newValue, forKey: "lidarXSign") }
    }
    static var lidarYSign: Double {
        get { 
            let val = UserDefaults.standard.double(forKey: "lidarYSign")
            return val == 0 ? 1.0 : val
        }
        set { UserDefaults.standard.set(newValue, forKey: "lidarYSign") }
    }
    static var lidarZSign: Double {
        get { 
            let val = UserDefaults.standard.double(forKey: "lidarZSign")
            return val == 0 ? 1.0 : val
        }
        set { UserDefaults.standard.set(newValue, forKey: "lidarZSign") }
    }
    static var lidarXSource: String {
        get { UserDefaults.standard.string(forKey: "lidarXSource") ?? "X" }
        set { UserDefaults.standard.set(newValue, forKey: "lidarXSource") }
    }
    static var lidarYSource: String {
        get { UserDefaults.standard.string(forKey: "lidarYSource") ?? "Y" }
        set { UserDefaults.standard.set(newValue, forKey: "lidarYSource") }
    }
    static var lidarZSource: String {
        get { UserDefaults.standard.string(forKey: "lidarZSource") ?? "Z" }
        set { UserDefaults.standard.set(newValue, forKey: "lidarZSource") }
    }
    static var selectedLens: String {
        get { UserDefaults.standard.string(forKey: "selectedLens") ?? "Wide" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedLens") }
    }
    static var is4KEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "is4KEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "is4KEnabled") }
    }
    static var videoCodec: String {
        get { UserDefaults.standard.string(forKey: "videoCodec") ?? "H.264" }
        set { UserDefaults.standard.set(newValue, forKey: "videoCodec") }
    }
    static var lensDistortionK1: Double {
        get { UserDefaults.standard.double(forKey: "lensDistortionK1") }
        set { UserDefaults.standard.set(newValue, forKey: "lensDistortionK1") }
    }
    static var lensDistortionK2: Double {
        get { UserDefaults.standard.double(forKey: "lensDistortionK2") }
        set { UserDefaults.standard.set(newValue, forKey: "lensDistortionK2") }
    }
    static var ueMonitorURL: String {
        get { UserDefaults.standard.string(forKey: "ueMonitorURL") ?? "http://192.168.1.100:80" }
        set { UserDefaults.standard.set(newValue, forKey: "ueMonitorURL") }
    }
}
