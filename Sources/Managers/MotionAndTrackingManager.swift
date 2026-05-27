import Foundation
import CoreMotion
import ARKit
import Combine

struct RawPoint3D: Identifiable, Hashable {
    let id = UUID()
    let x: Float
    let y: Float
    let z: Float
}

class MotionAndTrackingManager: NSObject, ObservableObject, ARSessionDelegate {
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    
    // ARKit Session for Foreground VIO + LiDAR
    var arSession = ARSession()
    
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
    
    private var cancellables = Set<AnyCancellable>()
    private var isAltimeterRunning = false
    
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
        isTrackingActive = true
        accumulatedPointCloud.removeAll()
        cameraTrajectory.removeAll()
        pointKeys.removeAll()
        
        startAltimeter()
        
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
    }
    
    // MARK: - ARKit Session Management (Foreground)
    
    private func startARKitSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("ARWorldTracking is not supported on this device.")
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading // Aligns Y-axis with gravity, X-axis with True North!
        
        // Select 4:3 video format if available to prevent cropping in the 4:3 viewports
        let targetRatio: CGFloat = 4.0 / 3.0
        if let format = ARWorldTrackingConfiguration.supportedVideoFormats.first(where: { format in
            let ratio = format.imageResolution.width / format.imageResolution.height
            return abs(ratio - targetRatio) < 0.02
        }) {
            configuration.videoFormat = format
            print("MotionAndTrackingManager: Configured native 4:3 AR video resolution: \(format.imageResolution)")
        }
        
        // Use LiDAR scene reconstruction if available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        // Enable scene depth frame semantics for ToF LiDAR depth projection
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        appState = "Foreground (ARKit VIO + LiDAR)"
    }
    
    func resumeARKitSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        
        // Select 4:3 video format if available to prevent cropping in the 4:3 viewports
        let targetRatio: CGFloat = 4.0 / 3.0
        if let format = ARWorldTrackingConfiguration.supportedVideoFormats.first(where: { format in
            let ratio = format.imageResolution.width / format.imageResolution.height
            return abs(ratio - targetRatio) < 0.02
        }) {
            configuration.videoFormat = format
        }
        
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
            self.yaw = attitude.yaw * (180.0 / .pi)
            
            self.q_w = attitude.quaternion.w
            self.q_x = attitude.quaternion.x
            self.q_y = attitude.quaternion.y
            self.q_z = attitude.quaternion.z
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
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isTrackingActive else { return }
        
        // Absolute precision: only process frame updates when visual-inertial tracking state is normal
        guard case .normal = frame.camera.trackingState else { return }
        
        let transform = frame.camera.transform
        let columns = transform.columns
        
        // Extract 3D translation vector (X, Y, Z coordinates in meters)
        // columns.3 is the position vector
        let tx = Double(columns.3.x)
        let ty = Double(columns.3.y)
        let tz = Double(columns.3.z)
        
        // Convert the 3x3 rotation matrix to Euler angles (degrees)
        let attitude = frame.camera.eulerAngles
        
        // Convert to Quaternions
        let quaternion = frame.camera.quaternion
        
        DispatchQueue.main.async {
            self.localX = tx
            self.localY = ty
            self.localZ = tz
            
            // eulerAngles represent pitch, yaw, roll in radians
            self.pitch = Double(attitude.x) * (180.0 / .pi)
            self.yaw = Double(attitude.y) * (180.0 / .pi)
            self.roll = Double(attitude.z) * (180.0 / .pi)
            
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
                }
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
    var eulerAngles: SIMD3<Float> {
        let transform = self.transform
        let r11 = transform.columns.0.x
        let r21 = transform.columns.0.y
        let r31 = transform.columns.0.z
        let r32 = transform.columns.1.z
        let r33 = transform.columns.2.z
        
        let pitch = atan2(-r32, r33)
        let yaw = atan2(r31, sqrt(r11*r11 + r21*r21))
        let roll = atan2(r21, r11)
        
        return SIMD3<Float>(pitch, yaw, roll)
    }
    
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
