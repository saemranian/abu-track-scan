import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var isGPSEnabled: Bool = true {
        didSet {
            if isGPSEnabled {
                startUpdates()
            } else {
                stopUpdates()
            }
        }
    }
    
    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var altitude: Double = 0.0
    @Published var horizontalAccuracy: Double = -1.0
    @Published var verticalAccuracy: Double = -1.0
    @Published var speed: Double = 0.0
    @Published var heading: Double = 0.0 // True North heading
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        
        // Allows background operations safely to avoid crashes if UIBackgroundModes lacks 'location'
        if let backgroundModes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String],
           backgroundModes.contains("location") {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        } else {
            NSLog("Warning: Background location updates not enabled in Info.plist / UIBackgroundModes")
        }
        locationManager.pausesLocationUpdatesAutomatically = false
        
        self.authorizationStatus = locationManager.authorizationStatus
    }
    
    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func startUpdates() {
        guard isGPSEnabled else { return }
        
        let status = locationManager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        } else {
            requestPermissions()
        }
    }
    
    func stopUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
                if self.isGPSEnabled {
                    self.startUpdates()
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.lastLocation = location
            self.latitude = location.coordinate.latitude
            self.longitude = location.coordinate.longitude
            self.altitude = location.altitude
            self.horizontalAccuracy = location.horizontalAccuracy
            self.verticalAccuracy = location.verticalAccuracy
            self.speed = location.speed
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            // Prefer True North if available, fallback to Magnetic North
            if newHeading.trueHeading >= 0 {
                self.heading = newHeading.trueHeading
            } else {
                self.heading = newHeading.magneticHeading
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed: \(error.localizedDescription)")
    }
}
