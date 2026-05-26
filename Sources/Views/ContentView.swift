import SwiftUI

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var trackingManager = MotionAndTrackingManager()
    
    @State private var selectedTab = 0
    @State private var requestedPermissions = false
    
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
        TabView(selection: $selectedTab) {
            DashboardView(locationManager: locationManager, trackingManager: trackingManager)
                .tabItem {
                    Image(systemName: "gyroscope")
                    Text("Dashboard")
                }
                .tag(0)
            
            SessionsView()
                .tabItem {
                    Image(systemName: "list.bullet.rectangle.portrait")
                    Text("Sessions")
                }
                .tag(1)
            
            SettingsView(locationManager: locationManager)
                .tabItem {
                    Image(systemName: "camera.aperture")
                    Text("Calibration")
                }
                .tag(2)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !requestedPermissions {
                locationManager.requestPermissions()
                requestedPermissions = true
            }
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
    static var captureRate: Double {
        get { 
            let rate = UserDefaults.standard.double(forKey: "captureRate")
            return rate == 0 ? 10.0 : rate
        }
        set { UserDefaults.standard.set(newValue, forKey: "captureRate") }
    }
    static var isGPSEnabled: Bool {
        get { 
            if UserDefaults.standard.object(forKey: "isGPSEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "isGPSEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "isGPSEnabled") }
    }
}
