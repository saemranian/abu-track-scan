import Foundation
import CoreMotion
import ARKit
import Combine
import SceneKit

struct RawPoint3D: Identifiable, Hashable {
    let id = UUID()
    let x: Float
    let y: Float
    let z: Float
}

class MotionAndTrackingManager: NSObject, ObservableObject, ARSessionDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    
    // ARKit Session for Foreground VIO + LiDAR
    var arSession = ARSession()
    
    // Stable, persistent ARSCNView to prevent metal deadlocks / freezes during tab transitions
    lazy var persistentARView: ARSCNView = {
        let scnView = ARSCNView(frame: .zero)
        scnView.session = arSession
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = true
        return scnView
    }()
    
    @Published var isTrackingActive: Bool = false
    @Published var appState: String = "Foreground (ARKit VIO Active)"
    
    // Real-time attitude data (Euler angles in degrees)
    @Published var pitch: Double = 0.0
    @Published var roll: Double = 0.0
    @Published var yaw: Double = 0.0
    
    // Quaternion data
    @Published var q_w: Double = 1.0
    @Published var q_x: Double = 0.0
    @Published var q_y: Double = 0.0
    @Published var q_z: Double = 0.0
    
    // Local VIO coordinates in meters
    @Published var localX: Double = 0.0
    @Published var localY: Double = 0.0
    @Published var localZ: Double = 0.0
    
    // Barometer relative altitude & pressure
    @Published var relativeAltitude: Double = 0.0
    @Published var pressureInKPa: Double = 101.325
    @Published var barometerActive: Bool = false
    
    // Magnetic field accuracy
    @Published var magneticCalibration: String = "Unknown"
    
    // Sparse point cloud for live 3D coverage mapping
    @Published var sparsePointCloud: [RawPoint3D] = []
    
    // Accumulated point cloud and camera trajectory path for reconstruction review
    @Published var accumulatedPointCloud: [RawPoint3D] = []
    @Published var cameraTrajectory: [RawPoint3D] = []
    private var pointKeys = Set<String>()
    
    // Toggle active depth/LiDAR scanning & point cloud reconstruction
    @Published var isMappingSensorsActive: Bool = true
    
    // Low-Latency H.264 Video Streaming Settings
    @Published var isLiveVideoStreamingEnabled: Bool = UserDefaults.standard.bool(forKey: "isLiveVideoStreamingEnabled") {
        didSet {
            UserDefaults.standard.set(isLiveVideoStreamingEnabled, forKey: "isLiveVideoStreamingEnabled")
        }
    }
    @Published var videoStreamPort: Int = UserDefaults.standard.integer(forKey: "videoStreamPort") == 0 ? 8082 : UserDefaults.standard.integer(forKey: "videoStreamPort") {
        didSet {
            UserDefaults.standard.set(videoStreamPort, forKey: "videoStreamPort")
        }
    }
    @Published var videoStreamQuality: String = UserDefaults.standard.string(forKey: "videoStreamQuality") ?? "Medium (540p @ 1.5Mbps)" {
        didSet {
            UserDefaults.standard.set(videoStreamQuality, forKey: "videoStreamQuality")
        }
    }
    @Published var videoStreamDiagLevel: Int = UserDefaults.standard.integer(forKey: "videoStreamDiagLevel") == 0 ? 4 : UserDefaults.standard.integer(forKey: "videoStreamDiagLevel") {
        didSet {
            UserDefaults.standard.set(videoStreamDiagLevel, forKey: "videoStreamDiagLevel")
        }
    }
    
    func diagLevelDescription(for level: Int) -> String {
        switch level {
        case 1: return "Lvl 1: Socket Only (No GPU Copy, No H.264 Encoder, No Network Video Packets)"
        case 2: return "Lvl 2: GPU Transfer Only (Allocates Pool Buffer + GPU Transfer, skips Encoder & Network)"
        case 3: return "Lvl 3: Encoder Dry-Run (GPU Transfer + hardware compression, exits before UDP/Network)"
        case 4: return "Lvl 4: Full H.264 RTP Stream (Complete pipeline, default)"
        default: return "Lvl 4: Full H.264 RTP Stream (Complete pipeline, default)"
        }
    }
    private let videoEncodingQueue = DispatchQueue(label: "com.abutrack.videoencoding.dispatch", qos: .userInteractive)
    
    // New point cloud points queue for live network stream to desktop app
    var newPointsQueue: [RawPoint3D] = []
    
    // Capturing Session Properties
    @Published var sessionTimer: DispatchSourceTimer? = nil
    @Published var sessionDuration: TimeInterval = 0.0
    @Published var entryCount: Int = 0
    @Published var activeSessionID: String? = nil
    @Published var startTime: Date? = nil
    @Published var hardwareScanHz: Double = 0.0
    @Published var currentFocalLength: Double = 24.0
    private var lastFrameTime: TimeInterval = 0
    
    
    private var cancellables = Set<AnyCancellable>()
    private var isAltimeterRunning = false
    private var lastStreamTime: TimeInterval = 0
    
    // Cached origin offset overrides for low-overhead thread-safe tracking updates
    private var cachedOriginOffsetX: Double = 0.0
    private var cachedOriginOffsetY: Double = 0.0
    private var cachedOriginOffsetZ: Double = 0.0
    private var cachedOriginOffsetYaw: Double = 0.0
    private var cachedYawOffsetRad: Double = 0.0
    
    private var cachedLeverArmX: Double = 0.0
    private var cachedLeverArmY: Double = 0.0
    private var cachedLeverArmZ: Double = 0.0
    
    private var cachedLidarXSign: Float = 1.0
    private var cachedLidarYSign: Float = 1.0
    private var cachedLidarZSign: Float = 1.0
    private var cachedLidarXSource: String = "X"
    private var cachedLidarYSource: String = "Y"
    private var cachedLidarZSource: String = "Z"
    
    override init() {
        super.init()
        arSession.delegate = self
        
        // Listen to App Lifecycle transitions to switch between ARKit and CoreMotion
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.handleAppDidEnterBackground() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.handleAppWillEnterForeground() }
            .store(in: &cancellables)
    }
    
    func startTracking(frequency: Double = 30.0) {
        // Cache the latest user configurations once at session start
        cachedOriginOffsetX = RigSettings.originOffsetX
        cachedOriginOffsetY = RigSettings.originOffsetY
        cachedOriginOffsetZ = RigSettings.originOffsetZ
        cachedOriginOffsetYaw = RigSettings.originOffsetYaw
        cachedYawOffsetRad = RigSettings.originOffsetYaw * (.pi / 180.0)
        
        cachedLeverArmX = RigSettings.leverArmX / 100.0
        cachedLeverArmY = RigSettings.leverArmY / 100.0
        cachedLeverArmZ = RigSettings.leverArmZ / 100.0
        
        cachedLidarXSign = Float(RigSettings.lidarXSign)
        cachedLidarYSign = Float(RigSettings.lidarYSign)
        cachedLidarZSign = Float(RigSettings.lidarZSign)
        cachedLidarXSource = RigSettings.lidarXSource
        cachedLidarYSource = RigSettings.lidarYSource
        cachedLidarZSource = RigSettings.lidarZSource
        
        isTrackingActive = true
        accumulatedPointCloud.removeAll()
        cameraTrajectory.removeAll()
        pointKeys.removeAll()
        
        startAltimeter()
        
        if isLiveVideoStreamingEnabled {
            let targetIP = UserDefaults.standard.string(forKey: "streamIP") ?? "192.168.1.100"
            let firstIP = targetIP.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "192.168.1.100"
            
            var width: Int32 = 960
            var height: Int32 = 540
            var bitrate: Int = 1_500_000
            
            let quality = videoStreamQuality
            if quality.contains("Low") {
                width = 640
                height = 480
                bitrate = 800_000
            } else if quality.contains("Medium") {
                width = 960
                height = 540
                bitrate = 1_500_000
            } else if quality.contains("High") {
                width = 1280
                height = 720
                bitrate = 3_000_000
            } else if quality.contains("Cinematic") || quality.contains("Max") {
                width = 1920
                height = 1080
                bitrate = 8_000_000
            }
            
            let codec = RigSettings.videoCodec
            LiveVideoStreamingManager.shared.startStreaming(ip: firstIP, port: videoStreamPort, width: width, height: height, bitrate: bitrate, codec: codec, diagLevel: videoStreamDiagLevel)
        }
        
        if UIApplication.shared.applicationState == .active {
            startARKitSession()
        } else {
            startCoreMotionUpdates(frequency: frequency)
        }
    }
    
    func stopTracking() {
        isTrackingActive = false
        stopARKitSession()
        stopCoreMotionUpdates()
        stopAltimeter()
        stopSessionTimer()
        configureFrontCameraSession(forceStop: true)
        LiveVideoStreamingManager.shared.stopStreaming()
    }
    
    func startSessionTimer(captureRate: Double) {
        stopSessionTimer()
        
        let sessionID = TelemetryLogger.shared.startNewSession()
        self.activeSessionID = sessionID
        self.startTime = Date()
        self.entryCount = 0
        self.sessionDuration = 0.0
        
        let queue = DispatchQueue(label: "com.abutrack.sessiontimer", qos: .userInteractive)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let intervalNs = Int(1_000_000_000.0 / captureRate)
        
        timer.schedule(deadline: .now(), repeating: .nanoseconds(intervalNs), leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isTrackingActive else { return }
            
            // Synthesize Abu Clock Kalman-PLL disciplined TAI & SMPTE ST 12-1 stamp
            let stamp = AbuClockKitBridge.shared.stampMonotonicNanoseconds(AbuClockKitBridge.currentMachNanoseconds())
            let disciplinedUtcMs = max((Double(stamp.disciplinedTaiNanoseconds) * 1.0e-9) - AbuClockKitBridge.taiMinusUtcSeconds, Date().timeIntervalSince1970) * 1000.0
            
            // Log Telemetry Record
            let entry = TelemetryEntry(
                timestamp: disciplinedUtcMs,
                localX: self.localX,
                localY: self.localY,
                localZ: self.localZ,
                relativeAltitude: self.relativeAltitude,
                pressure: self.pressureInKPa,
                pitch: self.pitch,
                roll: self.roll,
                yaw: self.yaw,
                q_w: self.q_w,
                q_x: self.q_x,
                q_y: self.q_y,
                q_z: self.q_z,
                isGPSEnabled: UserDefaults.standard.bool(forKey: "isGPSEnabled"),
                latitude: 0.0,
                longitude: 0.0,
                gpsAltitude: 0.0,
                horizontalAccuracy: 0.0,
                verticalAccuracy: 0.0,
                taiNs: stamp.disciplinedTaiNanoseconds,
                smpteTimecode: stamp.smpteWithSubframe,
                bcdTimecode: stamp.bcdTimecode,
                subframePhase: stamp.subframePhase,
                clockLockState: stamp.clockLockState
            )
            
            TelemetryLogger.shared.log(entry)
            
            DispatchQueue.main.async {
                guard let start = self.startTime else { return }
                self.sessionDuration = Date().timeIntervalSince(start)
                self.entryCount += 1
                
                let ptsToSend = self.newPointsQueue
                self.newPointsQueue.removeAll()
                
                let k1 = RigSettings.lensDistortionK1
                let k2 = RigSettings.lensDistortionK2
                let codec = RigSettings.videoCodec
                
                // Broadcast live UDP packets with coordinate mappings applied and points queue
                UDPStreamingManager.shared.stream(
                    x: self.localX,
                    y: self.localY,
                    z: self.localZ,
                    yaw: self.yaw,
                    pitch: self.pitch,
                    roll: self.roll,
                    focalLength: self.currentFocalLength,
                    k1: k1,
                    k2: k2,
                    videoCodec: codec,
                    newPoints: ptsToSend,
                    isMappingActive: self.isMappingSensorsActive
                )
            }
        }
        
        self.sessionTimer = timer
        timer.resume()
    }
    
    func stopSessionTimer() {
        sessionTimer?.cancel()
        sessionTimer = nil
    }
    
    func rescheduleSessionTimer(newRate: Double) {
        guard let timer = sessionTimer else { return }
        print("MotionAndTrackingManager: Rescheduling persistent session timer to \(newRate) Hz")
        let intervalNs = Int(1_000_000_000.0 / newRate)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(intervalNs), leeway: .nanoseconds(0))
    }
    
    // MARK: - ARKit Session Management (Foreground)
    
    private func selectVideoFormat(forConfiguration configuration: ARWorldTrackingConfiguration) {
        let lens = RigSettings.selectedLens
        var targetDeviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
        var targetPosition: AVCaptureDevice.Position = .back
        
        if lens == "UltraWide" {
            targetDeviceType = .builtInUltraWideCamera
        } else if lens == "Telephoto" {
            targetDeviceType = .builtInTelephotoCamera
        } else if lens == "Front" {
            targetDeviceType = .builtInTrueDepthCamera
            targetPosition = .front
        }
        
        let is4K = RigSettings.is4KEnabled
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats
        
        var filtered = formats.filter { $0.captureDevicePosition == targetPosition }
        let typeFiltered = filtered.filter { $0.captureDeviceType == targetDeviceType }
        if !typeFiltered.isEmpty {
            filtered = typeFiltered
        }
        
        var format: ARConfiguration.VideoFormat? = nil
        if is4K {
            format = filtered.first { f in
                let w = f.imageResolution.width
                let h = f.imageResolution.height
                return (w == 3840 && h == 2160) || (w == 2160 && h == 3840)
            }
            if format == nil {
                format = filtered.max(by: { f1, f2 in
                    (f1.imageResolution.width * f1.imageResolution.height) < (f2.imageResolution.width * f2.imageResolution.height)
                })
            }
        }
        
        if format == nil {
            let targetRatio: CGFloat = 4.0 / 3.0
            format = filtered.first(where: { f in
                let ratio = f.imageResolution.width / f.imageResolution.height
                let is43 = abs(ratio - targetRatio) < 0.02
                return is43 && f.isRecommendedForHighResolutionFrameCapturing
            }) ?? filtered.first(where: { f in
                let ratio = f.imageResolution.width / f.imageResolution.height
                return abs(ratio - targetRatio) < 0.02
            }) ?? filtered.first
        }
        
        if let format = format {
            configuration.videoFormat = format
            print("MotionAndTrackingManager: Configured native AR video format: \(format.imageResolution)")
        }
    }
    
    func updateCameraConfiguration() {
        guard isTrackingActive else { return }
        
        DispatchQueue.main.async {
            guard ARWorldTrackingConfiguration.isSupported else { return }
            
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravityAndHeading
            
            self.selectVideoFormat(forConfiguration: configuration)
            
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
            }
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            
            self.arSession.run(configuration, options: [])
            self.configureFrontCameraSession()
        }
    }
    
    private func startARKitSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("ARWorldTracking is not supported on this device.")
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading // Aligns Y-axis with gravity, X-axis with True North!
        
        selectVideoFormat(forConfiguration: configuration)
        
        // Use LiDAR scene reconstruction if available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        // Enable scene depth frame semantics for ToF LiDAR depth projection
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        configureFrontCameraSession()
        appState = "Foreground (ARKit VIO + LiDAR)"
    }
    
    func resumeARKitSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        
        selectVideoFormat(forConfiguration: configuration)
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        arSession.run(configuration, options: [])
        appState = "Foreground (ARKit VIO + LiDAR)"
    }
    
    private func stopARKitSession() {
        arSession.pause()
        configureFrontCameraSession(forceStop: true)
    }
    
    // MARK: - CoreMotion Management (Background Fallback)
    
    private func startCoreMotionUpdates(frequency: Double) {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / frequency
        // Align reference frame with gravity and true north
        let frame: CMAttitudeReferenceFrame = .xMagneticNorthZVertical
        
        motionManager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] (motion, error) in
            guard let self = self, let motion = motion, self.isTrackingActive else { return }
            
            // Only update if in background (otherwise ARKit handles updates)
            if UIApplication.shared.applicationState == .background {
                self.updateAttitude(attitude: motion.attitude)
                self.updateMagneticCalibration(calibration: motion.magneticField.accuracy)
            }
        }
        appState = "Background (CoreMotion Active)"
    }
    
    private func stopCoreMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    // MARK: - Barometer (Altimeter) Updates
    
    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            barometerActive = false
            return
        }
        
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data, self.isTrackingActive else { return }
            
            DispatchQueue.main.async {
                self.relativeAltitude = data.relativeAltitude.doubleValue
                self.pressureInKPa = data.pressure.doubleValue // In kilopascals
                self.barometerActive = true
            }
        }
        isAltimeterRunning = true
    }
    
    private func stopAltimeter() {
        if isAltimeterRunning {
            altimeter.stopRelativeAltitudeUpdates()
            isAltimeterRunning = false
        }
    }
    
    // MARK: - App Lifecycle Handlers
    
    private func handleAppDidEnterBackground() {
        guard isTrackingActive else { return }
        stopARKitSession()
        startCoreMotionUpdates(frequency: 30.0)
    }
    
    private func handleAppWillEnterForeground() {
        guard isTrackingActive else { return }
        stopCoreMotionUpdates()
        startARKitSession()
    }
    
    // MARK: - Data Processing
    
    private func updateAttitude(attitude: CMAttitude) {
        DispatchQueue.main.async {
            // Convert radians to degrees
            self.pitch = attitude.pitch * (180.0 / .pi)
            self.roll = attitude.roll * (180.0 / .pi)
            
            var adjustedYaw = attitude.yaw * (180.0 / .pi) + self.cachedOriginOffsetYaw
            if adjustedYaw > 180 {
                adjustedYaw -= 360
            } else if adjustedYaw < -180 {
                adjustedYaw += 360
            }
            self.yaw = adjustedYaw
            
            if self.cachedYawOffsetRad != 0 {
                let offsetQuat = simd_quatd(angle: self.cachedYawOffsetRad, axis: simd_double3(0, 1, 0))
                let qCam = simd_quatd(ix: attitude.quaternion.x, iy: attitude.quaternion.y, iz: attitude.quaternion.z, r: attitude.quaternion.w)
                let rotatedQuat = offsetQuat * qCam
                self.q_w = rotatedQuat.vector.w
                self.q_x = rotatedQuat.vector.x
                self.q_y = rotatedQuat.vector.y
                self.q_z = rotatedQuat.vector.z
            } else {
                self.q_w = attitude.quaternion.w
                self.q_x = attitude.quaternion.x
                self.q_y = attitude.quaternion.y
                self.q_z = attitude.quaternion.z
            }
        }
    }
    
    private func updateMagneticCalibration(calibration: CMMagneticFieldCalibrationAccuracy) {
        DispatchQueue.main.async {
            switch calibration {
            case .uncalibrated: self.magneticCalibration = "Uncalibrated"
            case .low: self.magneticCalibration = "Low"
            case .medium: self.magneticCalibration = "Medium"
            case .high: self.magneticCalibration = "High"
            @unknown default: self.magneticCalibration = "Unknown"
            }
        }
    }
    
    // Parallel AVCaptureSession for Front Camera streaming
    private var frontCameraSession: AVCaptureSession?
    private var frontVideoOutput: AVCaptureVideoDataOutput?
    private let frontSessionQueue = DispatchQueue(label: "com.camtrack.frontSessionQueue")
    
    private struct LensOffsets {
        let ultraWide: simd_double3
        let telephoto: simd_double3
        let front: simd_double3
    }
    
    private func getDeviceOffsets() -> LensOffsets {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // Map to standard offsets in meters (Wide to other lenses)
        if identifier.hasPrefix("iPhone16,") || identifier.hasPrefix("iPhone17,") {
            // iPhone 15 Pro / 15 Pro Max & 16 Pro / 16 Pro Max
            return LensOffsets(
                ultraWide: simd_double3(0.0155, -0.0122, 0.0),
                telephoto: simd_double3(0.0, -0.0245, 0.0),
                front: simd_double3(-0.0162, 0.0125, -0.0082)
            )
        } else if identifier.hasPrefix("iPhone15,") || identifier.hasPrefix("iPhone14,") {
            // iPhone 14 Pro / 14 Pro Max & 13 Pro / 13 Pro Max
            return LensOffsets(
                ultraWide: simd_double3(0.0145, -0.0118, 0.0),
                telephoto: simd_double3(0.0, -0.0232, 0.0),
                front: simd_double3(-0.0150, 0.0115, -0.0078)
            )
        } else {
            // Default Fallback
            return LensOffsets(
                ultraWide: simd_double3(0.0150, -0.0120, 0.0),
                telephoto: simd_double3(0.0, -0.0240, 0.0),
                front: simd_double3(-0.0150, 0.0120, -0.0080)
            )
        }
    }
    
    func getDefaultDistortion(for lens: String) -> (Double, Double) {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(Unicode.Scalar(UInt8(value))))
        }
        
        if identifier.hasPrefix("iPhone16,") || identifier.hasPrefix("iPhone17,") {
            // iPhone 15 Pro / 15 Pro Max & 16 Pro / 16 Pro Max
            switch lens {
            case "UltraWide": return (-0.075, 0.015)
            case "Telephoto": return (0.001, 0.0)
            case "Front":     return (-0.012, 0.003)
            default:          return (0.005, -0.002) // Wide (Main)
            }
        } else if identifier.hasPrefix("iPhone15,") || identifier.hasPrefix("iPhone14,") {
            // iPhone 14 Pro / 14 Pro Max & 13 Pro / 13 Pro Max
            switch lens {
            case "UltraWide": return (-0.080, 0.018)
            case "Telephoto": return (0.001, 0.0)
            case "Front":     return (-0.014, 0.004)
            default:          return (0.006, -0.002) // Wide (Main)
            }
        } else {
            // Default Fallback
            switch lens {
            case "UltraWide": return (-0.078, 0.016)
            case "Telephoto": return (0.0, 0.0)
            case "Front":     return (-0.013, 0.003)
            default:          return (0.0, 0.0) // Wide (Main)
            }
        }
    }
    
    private func configureFrontCameraSession(forceStop: Bool = false) {
        frontSessionQueue.async { [weak self] in
            guard let self = self else { return }
            let selectedLens = RigSettings.selectedLens
            
            if selectedLens == "Front" && !forceStop {
                if self.frontCameraSession != nil { return } // Already running
                
                print("MotionAndTrackingManager: Initializing parallel Front Camera capture session")
                let session = AVCaptureSession()
                session.beginConfiguration()
                
                let deviceDiscovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
                    mediaType: .video,
                    position: .front
                )
                
                guard let frontDevice = deviceDiscovery.devices.first else {
                    print("MotionAndTrackingManager: No front camera device found.")
                    session.commitConfiguration()
                    return
                }
                
                do {
                    let input = try AVCaptureDeviceInput(device: frontDevice)
                    if session.canAddInput(input) {
                        session.addInput(input)
                    }
                    
                    let videoOutput = AVCaptureVideoDataOutput()
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                    
                    if session.canAddOutput(videoOutput) {
                        session.addOutput(videoOutput)
                        videoOutput.setSampleBufferDelegate(self, queue: self.frontSessionQueue)
                    }
                    
                    if RigSettings.is4KEnabled && session.canSetSessionPreset(.hd4K3840x2160) {
                        session.sessionPreset = .hd4K3840x2160
                    } else if session.canSetSessionPreset(.hd1920x1080) {
                        session.sessionPreset = .hd1920x1080
                    }
                    
                    session.commitConfiguration()
                    session.startRunning()
                    
                    self.frontCameraSession = session
                    self.frontVideoOutput = videoOutput
                    print("MotionAndTrackingManager: Front camera capture session started.")
                } catch {
                    print("MotionAndTrackingManager: Failed to configure front camera input: \(error)")
                    session.commitConfiguration()
                }
            } else {
                if let session = self.frontCameraSession {
                    print("MotionAndTrackingManager: Stopping parallel Front Camera capture session")
                    session.stopRunning()
                    self.frontCameraSession = nil
                    self.frontVideoOutput = nil
                }
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isTrackingActive && isLiveVideoStreamingEnabled else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ntpSyncOffset = NTPSyncClient.shared.isSynced ? NTPSyncClient.shared.clockOffset : 0.0
        let ntpTime = Date().timeIntervalSince1970 + ntpSyncOffset
        LiveVideoStreamingManager.shared.encodeAndStream(pixelBuffer: pixelBuffer, ntpTimestamp: ntpTime)
    }

    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isTrackingActive else { return }
        
        // Absolute precision: only process frame updates when visual-inertial tracking state is normal
        guard case .normal = frame.camera.trackingState else { return }
        
        let selectedLens = RigSettings.selectedLens
        let equivalentFocalLength = Double(frame.camera.intrinsics[0][0]) * (36.0 / Double(frame.camera.imageResolution.width))
        DispatchQueue.main.async {
            self.currentFocalLength = equivalentFocalLength
        }
        
        if isLiveVideoStreamingEnabled && selectedLens != "Front" {
            let pixelBuffer = frame.capturedImage
            let ntpSyncOffset = NTPSyncClient.shared.isSynced ? NTPSyncClient.shared.clockOffset : 0.0
            let ntpTime = Date().timeIntervalSince1970 + ntpSyncOffset
            LiveVideoStreamingManager.shared.encodeAndStream(pixelBuffer: pixelBuffer, ntpTimestamp: ntpTime)
        }
        
        let currentFrameTime = frame.timestamp
        if lastFrameTime > 0 {
            let diff = currentFrameTime - lastFrameTime
            if diff > 0 {
                let currentHz = 1.0 / diff
                DispatchQueue.main.async {
                    self.hardwareScanHz = (self.hardwareScanHz * 0.95) + (currentHz * 0.05)
                }
            }
        }
        lastFrameTime = currentFrameTime
        
        let transform = frame.camera.transform
        let columns = transform.columns
        
        // Resolve dynamic device-model-specific physical offsets from the Wide camera to the selected lens
        let offsets = getDeviceOffsets()
        var lensOffset = simd_double3(0, 0, 0)
        if selectedLens == "UltraWide" {
            lensOffset = offsets.ultraWide
        } else if selectedLens == "Telephoto" {
            lensOffset = offsets.telephoto
        } else if selectedLens == "Front" {
            lensOffset = offsets.front
        }
        
        // Convert to Quaternions & Apply Yaw offsets
        var quaternion = frame.camera.quaternion
        
        // Rotate local lens offset using VIO orientation (in camera coordinates)
        var rotatedOffset = quaternion.act(lensOffset)
        if selectedLens == "Front" {
            // Apply 180-degree rotational offset to the translation offset calculation
            let y180Quat = simd_quatd(angle: .pi, axis: simd_double3(0, 1, 0))
            let frontRotation = quaternion * y180Quat
            rotatedOffset = frontRotation.act(lensOffset)
        }
        
        // Apply VIO translation modified by the physical lens offset
        var px = Double(columns.3.x) + rotatedOffset.x
        var py = Double(columns.3.y) + rotatedOffset.y
        var pz = Double(columns.3.z) + rotatedOffset.z
        
        // Convert the 3x3 rotation matrix to Euler angles (degrees)
        var attitude = frame.camera.eulerAngles
        
        if cachedYawOffsetRad != 0 {
            let offsetQuat = simd_quatd(angle: cachedYawOffsetRad, axis: simd_double3(0, 1, 0))
            quaternion = offsetQuat * quaternion
        }
        
        // If front camera, apply a 180 degrees rotational offset around the vertical axis
        if selectedLens == "Front" {
            let y180Quat = simd_quatd(angle: .pi, axis: simd_double3(0, 1, 0))
            quaternion = quaternion * y180Quat
        }
        
        // 2. Apply DSLR Lever Arm offset (local space to world space rotation)
        let lx = cachedLeverArmX
        let ly = cachedLeverArmY
        let lz = cachedLeverArmZ
        if lx != 0.0 || ly != 0.0 || lz != 0.0 {
            let qw = quaternion.vector.w
            let qx = quaternion.vector.x
            let qy = quaternion.vector.y
            let qz = quaternion.vector.z
            
            let num1 = qx * 2.0
            let num2 = qy * 2.0
            let num3 = qz * 2.0
            let num4 = qx * num1
            let num5 = qy * num2
            let num6 = qz * num3
            let num7 = qx * num2
            let num8 = qx * num3
            let num9 = qy * num3
            let num10 = qw * num1
            let num11 = qw * num2
            let num12 = qw * num3
            
            let rx = (1.0 - (num5 + num6)) * lx + (num7 - num12) * ly + (num8 + num11) * lz
            let ry = (num7 + num12) * lx + (1.0 - (num4 + num6)) * ly + (num9 - num10) * lz
            let rz = (num8 - num11) * lx + (num9 + num10) * ly + (1.0 - (num4 + num5)) * lz
            
            px -= rx
            py -= ry
            pz -= rz
        }
        
        // 3. Apply static Origin Offset
        let tx = px + cachedOriginOffsetX
        let ty = py + cachedOriginOffsetY
        let tz = pz + cachedOriginOffsetZ
        
        // Background real-time streaming is disabled to lock it strictly to the Dashboard capture session GCD timer
        
        DispatchQueue.main.async {
            self.localX = tx
            self.localY = ty
            self.localZ = tz
            
            if selectedLens == "Front" {
                // Invert pitch and roll, rotate yaw by 180 degrees for opposite facing selfie view
                self.pitch = -Double(attitude.x) * (180.0 / .pi)
                var adjustedYaw = Double(attitude.y) * (180.0 / .pi) + 180.0 + self.cachedOriginOffsetYaw
                if adjustedYaw > 180 {
                    adjustedYaw -= 360
                } else if adjustedYaw < -180 {
                    adjustedYaw += 360
                }
                self.yaw = adjustedYaw
                self.roll = -Double(attitude.z) * (180.0 / .pi)
            } else {
                self.pitch = Double(attitude.x) * (180.0 / .pi)
                var adjustedYaw = Double(attitude.y) * (180.0 / .pi) + self.cachedOriginOffsetYaw
                if adjustedYaw > 180 {
                    adjustedYaw -= 360
                } else if adjustedYaw < -180 {
                    adjustedYaw += 360
                }
                self.yaw = adjustedYaw
                self.roll = Double(attitude.z) * (180.0 / .pi)
            }
            
            self.q_w = quaternion.vector.w
            self.q_x = quaternion.vector.x
            self.q_y = quaternion.vector.y
            self.q_z = quaternion.vector.z
            
            self.appState = "Foreground (ARKit VIO + LiDAR)"
            
            // Record camera trajectory if it has moved at least 2cm from the last position
            let lastPoint = self.cameraTrajectory.last
            let dx = Float(tx) - (lastPoint?.x ?? 999.0)
            let dy = Float(ty) - (lastPoint?.y ?? 999.0)
            let dz = Float(tz) - (lastPoint?.z ?? 999.0)
            let dist = sqrt(dx*dx + dy*dy + dz*dz)
            if dist > 0.02 {
                self.cameraTrajectory.append(RawPoint3D(x: Float(tx), y: Float(ty), z: Float(tz)))
            }
            
            // Extract high-precision LiDAR depth points (or fall back to sparse VIO points if unavailable)
            var currentFramePoints: [RawPoint3D] = []
            if self.isMappingSensorsActive {
                let lidarPoints = self.extractLiDARPoints(from: frame)
                
                let hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
                
                if !lidarPoints.isEmpty {
                    currentFramePoints = lidarPoints
                } else if !hasLiDAR, let rawFeaturePoints = frame.rawFeaturePoints {
                    let points = rawFeaturePoints.points
                    let maxPoints = min(points.count, 200)
                    for i in 0..<maxPoints {
                        let pt = points[i]
                        currentFramePoints.append(RawPoint3D(x: pt.x, y: pt.y, z: pt.z))
                    }
                }
                
                // Map the point cloud points to the offset origin space using translation and yaw offsets
                let cosYaw = Float(cos(self.cachedYawOffsetRad))
                let sinYaw = Float(sin(self.cachedYawOffsetRad))
                let offX = Float(self.cachedOriginOffsetX)
                let offY = Float(self.cachedOriginOffsetY)
                let offZ = Float(self.cachedOriginOffsetZ)
                
                let mappedPoints = currentFramePoints.map { pt -> RawPoint3D in
                    let inputs = ["X": pt.x, "Y": pt.y, "Z": pt.z]
                    let mx = (inputs[self.cachedLidarXSource] ?? pt.x) * self.cachedLidarXSign
                    let my = (inputs[self.cachedLidarYSource] ?? pt.y) * self.cachedLidarYSign
                    let mz = (inputs[self.cachedLidarZSource] ?? pt.z) * self.cachedLidarZSign
                    
                    var rx = mx
                    var rz = mz
                    if self.cachedYawOffsetRad != 0 {
                        rx = mx * cosYaw - mz * sinYaw
                        rz = mx * sinYaw + mz * cosYaw
                    }
                    return RawPoint3D(x: rx + offX, y: my + offY, z: rz + offZ)
                }
                currentFramePoints = mappedPoints
                
                // Limit points logged to sparsePointCloud to prevent memory overload in UI
                self.sparsePointCloud = Array(currentFramePoints.prefix(200))
                
                // Accumulate unique points using 3cm voxel grid keys to filter spatial tracking noise
                let voxelSize: Float = 0.03
                for pt in currentFramePoints {
                    let gridX = Int(round(pt.x / voxelSize))
                    let gridY = Int(round(pt.y / voxelSize))
                    let gridZ = Int(round(pt.z / voxelSize))
                    let key = "\(gridX),\(gridY),\(gridZ)"
                    if !self.pointKeys.contains(key) {
                        self.pointKeys.insert(key)
                        self.accumulatedPointCloud.append(pt)
                        self.newPointsQueue.append(pt)
                    }
                }
            } else {
                self.sparsePointCloud.removeAll()
            }
        }
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        DispatchQueue.main.async {
            switch camera.trackingState {
            case .notAvailable:
                self.appState = "ARKit Not Available"
            case .limited(let reason):
                switch reason {
                case .initializing:
                    self.appState = "ARKit Initializing..."
                case .excessiveMotion:
                    self.appState = "ARKit Warning: Excessive Motion"
                case .insufficientFeatures:
                    self.appState = "ARKit Warning: Insufficient Features"
                case .relocalizing:
                    self.appState = "ARKit Relocalizing..."
                @unknown default:
                    self.appState = "ARKit Limited"
                }
            case .normal:
                self.appState = "ARKit Active (LiDAR VIO)"
            }
        }
    }
    
    // Project scene depth map (LiDAR) into 3D world coordinates
    private func extractLiDARPoints(from frame: ARFrame) -> [RawPoint3D] {
        guard let sceneDepth = frame.sceneDepth else { return [] }
        
        let depthMap = sceneDepth.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let confidenceMap = sceneDepth.confidenceMap
        if let confidenceMap = confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        defer {
            if let confidenceMap = confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return [] }
        
        var confidenceBuffer: UnsafeMutablePointer<UInt8>? = nil
        var confidenceBytesPerRow = 0
        if let confidenceMap = confidenceMap, let addr = CVPixelBufferGetBaseAddress(confidenceMap) {
            confidenceBuffer = addr.assumingMemoryBound(to: UInt8.self)
            confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        
        let imgWidth = Float(CVPixelBufferGetWidth(frame.capturedImage))
        let imgHeight = Float(CVPixelBufferGetHeight(frame.capturedImage))
        let scaleX = imgWidth / Float(width)
        let scaleY = imgHeight / Float(height)
        
        var points: [RawPoint3D] = []
        
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]
        
        let transform = frame.camera.transform
        
        // Subsample rate (sample every 12th pixel in x/y to prevent UI rendering lag)
        let stepX = 12
        let stepY = 12
        
        if pixelFormat == kCVPixelFormatType_DepthFloat32 {
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
            for y in stride(from: 0, to: height, by: stepY) {
                for x in stride(from: 0, to: width, by: stepX) {
                    let pixelIndex = y * (bytesPerRow / 4) + x
                    let depth = floatBuffer[pixelIndex]
                    
                    var confidenceValue: UInt8 = 2 // Default to high confidence if missing
                    if let confBuf = confidenceBuffer {
                        confidenceValue = confBuf[y * confidenceBytesPerRow + x]
                    }
                    
                    // Filter out low confidence points (0) or only allow high (2) and medium (1)
                    if depth > 0.2 && depth < 3.0 && confidenceValue >= 1 {
                        // Project back to 3D camera space using scaled image coordinates
                        let imgX = Float(x) * scaleX
                        let imgY = Float(y) * scaleY
                        let camPoint = SIMD4<Float>(
                            (imgX - cx) * depth / fx,
                            -(imgY - cy) * depth / fy,
                            -depth,
                            1.0
                        )
                        let worldPoint = transform * camPoint
                        points.append(RawPoint3D(x: worldPoint.x, y: worldPoint.y, z: worldPoint.z))
                    }
                }
            }
        } else if pixelFormat == kCVPixelFormatType_DepthFloat16 {
            let halfBuffer = baseAddress.assumingMemoryBound(to: Float16.self)
            for y in stride(from: 0, to: height, by: stepY) {
                for x in stride(from: 0, to: width, by: stepX) {
                    let pixelIndex = y * (bytesPerRow / 2) + x
                    let depth = Float(halfBuffer[pixelIndex])
                    
                    var confidenceValue: UInt8 = 2 // Default to high confidence if missing
                    if let confBuf = confidenceBuffer {
                        confidenceValue = confBuf[y * confidenceBytesPerRow + x]
                    }
                    
                    if depth > 0.2 && depth < 3.0 && confidenceValue >= 1 {
                        let imgX = Float(x) * scaleX
                        let imgY = Float(y) * scaleY
                        let camPoint = SIMD4<Float>(
                            (imgX - cx) * depth / fx,
                            -(imgY - cy) * depth / fy,
                            -depth,
                            1.0
                        )
                        let worldPoint = transform * camPoint
                        points.append(RawPoint3D(x: worldPoint.x, y: worldPoint.y, z: worldPoint.z))
                    }
                }
            }
        }
        
        return points
    }
}

// ARKit Camera Extensions to extract Euler Angles and Quaternions easily
extension ARCamera {
    
    var quaternion: simd_quatd {
        // Convert simd_float4x4 rotation component to double-precision quaternion
        let rotMat = simd_double3x3(
            simd_double3(Double(self.transform.columns.0.x), Double(self.transform.columns.0.y), Double(self.transform.columns.0.z)),
            simd_double3(Double(self.transform.columns.1.x), Double(self.transform.columns.1.y), Double(self.transform.columns.1.z)),
            simd_double3(Double(self.transform.columns.2.x), Double(self.transform.columns.2.y), Double(self.transform.columns.2.z))
        )
        return simd_quaternion(rotMat)
    }
}
