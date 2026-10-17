import Foundation
import AVFoundation
import UIKit
import SwiftUI
import ImageIO

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didCapturePhotoAt url: URL, timestamp: Double, filename: String)
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error)
}

class CameraManager: NSObject, AVCapturePhotoCaptureDelegate, ObservableObject {
    private let captureSession = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.camtrack.camera.sessionQueue")
    
    weak var delegate: CameraManagerDelegate?
    
    private var activeSessionID: String?
    private var photoCounter = 1255 // Match system photos starting index
    private var isConfigured = false
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var selectedFormat = "JPG" // Selected picture format (JPG, HEIF, DNG)
    private var lastShutterStartMachNs: UInt64 = 0
    @Published var lastOpticalStamp: OpticalMidpointStamp?
    
    override init() {
        super.init()
        // Register for Abu Clock SCHEDULE_CAPTURE_AT future-time barrier triggers (UDP 50319)
        AbuClockKitBridge.shared.onScheduledCaptureTrigger = { [weak self] barrier, stamp in
            guard let self = self else { return }
            self.lastShutterStartMachNs = stamp.hostMachNanoseconds
            let fmt = (barrier.format ?? self.selectedFormat).uppercased()
            self.capturePhoto(format: fmt, is48MP: false)
        }
    }
    
    func setupCamera(completion: @escaping (Bool) -> Void) {
        sessionQueue.async {
            if self.isConfigured {
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
                completion(true)
                return
            }
            
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo // Maximum resolution
            
            // 1. Find physical main Wide-angle back camera (supports 48MP and manual exposure/focus locks)
            let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
            
            guard let videoDevice = deviceDiscoverySession.devices.first else {
                print("CameraManager: No back physical wide camera found")
                self.captureSession.commitConfiguration()
                completion(false)
                return
            }
            
            // Configure hardware settings for absolute best clarity
            do {
                try videoDevice.lockForConfiguration()
                
                // Select 48MP active format (dimensions >= 8000, e.g. 8064x6048) if supported
                if #available(iOS 16.0, *) {
                    if let highResFormat = videoDevice.formats.first(where: { format in
                        format.supportedMaxPhotoDimensions.contains(where: { $0.width >= 8000 })
                    }) {
                        videoDevice.activeFormat = highResFormat
                        print("CameraManager: Configured physical 48MP active format: \(highResFormat)")
                    }
                }
                
                if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                    videoDevice.focusMode = .continuousAutoFocus
                }
                if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                    videoDevice.exposureMode = .continuousAutoExposure
                }
                if videoDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    videoDevice.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                if videoDevice.isLowLightBoostSupported {
                    videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = true
                }
                videoDevice.unlockForConfiguration()
            } catch {
                print("CameraManager: Failed to configure device settings: \(error)")
            }
            
            // 2. Add video device input
            do {
                let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.captureSession.canAddInput(videoDeviceInput) {
                    self.captureSession.addInput(videoDeviceInput)
                    self.videoDeviceInput = videoDeviceInput
                } else {
                    print("CameraManager: Cannot add video input")
                    self.captureSession.commitConfiguration()
                    completion(false)
                    return
                }
            } catch {
                print("CameraManager: Cannot create video input: \(error)")
                self.captureSession.commitConfiguration()
                completion(false)
                return
            }
            
            // 3. Add high-resolution photo output
            let photoOutput = AVCapturePhotoOutput()
            if self.captureSession.canAddOutput(photoOutput) {
                self.captureSession.addOutput(photoOutput)
                self.photoOutput = photoOutput
                
                // Enable maximum high-resolution options safely
                photoOutput.isHighResolutionCaptureEnabled = true
                photoOutput.maxPhotoQualityPrioritization = .quality // DSLR-quality processing
                
                if #available(iOS 16.0, *) {
                    // Query the maximum dimensions supported by the active format of the back camera
                    if let videoDevice = self.videoDeviceInput?.device,
                       let maxDim = videoDevice.activeFormat.supportedMaxPhotoDimensions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                        photoOutput.maxPhotoDimensions = maxDim
                        print("CameraManager: Configured photoOutput max dimensions: \(maxDim)")
                    }
                }
            } else {
                print("CameraManager: Cannot add photo output")
                self.captureSession.commitConfiguration()
                completion(false)
                return
            }
            
            self.captureSession.commitConfiguration()
            
            self.isConfigured = true
            
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            completion(true)
        }
    }
    
    func startSession(sessionID: String) {
        self.activeSessionID = sessionID
        self.photoCounter = 1255 // Reset photo count index per run
    }
    
    func stopSession() {
        self.activeSessionID = nil
    }
    
    func stopHardwareSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                print("CameraManager: Hardware session stopped")
            }
        }
    }
    
    // Sets camera manual exposure & Kelvin white balance temperature dynamically
    func updateExposureAndWB(shutterSpeed: Double, iso: Double, wbTemperature: Double) {
        guard let device = videoDeviceInput?.device else { return }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                
                // 1. Exposure (shutterSpeed = 0.0 is automatic)
                if shutterSpeed == 0.0 {
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                } else {
                    if device.isExposureModeSupported(.custom) {
                        let minDuration = device.activeFormat.minExposureDuration
                        let maxDuration = device.activeFormat.maxExposureDuration
                        // Clamp exposure duration safely to prevent hardware crash
                        let targetSeconds = max(minDuration.seconds, min(maxDuration.seconds, shutterSpeed))
                        let duration = CMTime(seconds: targetSeconds, preferredTimescale: 1000000)
                        
                        let minISO = device.activeFormat.minISO
                        let maxISO = device.activeFormat.maxISO
                        let targetISO = max(minISO, min(maxISO, Float(iso == 0.0 ? Double(device.iso) : iso)))
                        
                        device.setExposureModeCustom(duration: duration, iso: targetISO, completionHandler: nil)
                    }
                }
                
                // 2. White Balance temperature settings (wbTemperature = 0.0 is automatic)
                if wbTemperature == 0.0 {
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                } else {
                    if device.isWhiteBalanceModeSupported(.locked) {
                        // Clamp white balance temperature to a highly compatible safe range to prevent crash
                        let safeTemperature = max(3000.0, min(8000.0, Float(wbTemperature)))
                        let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: safeTemperature, tint: 0.0)
                        let gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                        
                        var red = gains.redGain
                        var green = gains.greenGain
                        var blue = gains.blueGain
                        
                        if red.isNaN || red.isInfinite { red = 1.0 }
                        if green.isNaN || green.isInfinite { green = 1.0 }
                        if blue.isNaN || blue.isInfinite { blue = 1.0 }
                        
                        let maxGain = device.maxWhiteBalanceGain
                        let clampedGains = AVCaptureDevice.WhiteBalanceGains(
                            redGain: max(1.0, min(maxGain, red)),
                            greenGain: max(1.0, min(maxGain, green)),
                            blueGain: max(1.0, min(maxGain, blue))
                        )
                        
                        device.setWhiteBalanceModeLocked(with: clampedGains, completionHandler: nil)
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                print("CameraManager: Failed to configure exposure/WB parameters: \(error)")
            }
        }
    }
    
    // Sets camera focus mode and manual lens position (lensPosition = 0.0 is nearest, 1.0 is infinity/automatic)
    func updateFocus(isAutoFocus: Bool, lensPosition: Double) {
        guard let device = videoDeviceInput?.device else { return }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                
                if isAutoFocus {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                } else {
                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                        // Clamp focus lens position between 0.0 and 1.0 to prevent hardware crash
                        let clampedPosition = max(0.0, min(1.0, Float(lensPosition)))
                        device.setFocusModeLocked(lensPosition: clampedPosition, completionHandler: nil)
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                print("CameraManager: Failed to configure focus: \(error)")
            }
        }
    }
    
    // Sets active physical lens and digital zoom factor (from 1.0x to max hardware limits)
    func setZoomFactor(_ factor: Double) {
        guard let device = videoDeviceInput?.device else { return }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let clampedFactor = max(device.minAvailableVideoZoomFactor, min(device.maxAvailableVideoZoomFactor, CGFloat(factor)))
                device.videoZoomFactor = clampedFactor
                device.unlockForConfiguration()
            } catch {
                print("CameraManager: Failed to configure videoZoomFactor: \(error)")
            }
        }
    }
    
    func capturePhoto(format: String, is48MP: Bool) {
        sessionQueue.async {
            guard let photoOutput = self.photoOutput, self.captureSession.isRunning else {
                print("CameraManager: Output is nil or session not running")
                return
            }
            
            self.selectedFormat = format // Save active format choice
            var photoSettings = AVCapturePhotoSettings()
            
            // Resolve format constraints: DNG (RAW), HEIF, JPG
            if format == "DNG" && !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty {
                let rawFormatType = photoOutput.availableRawPhotoPixelFormatTypes.first!
                photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormatType, processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else if format == "HEIF" && photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
            
            // Set high-resolution options safely
            photoSettings.isHighResolutionPhotoEnabled = true
            photoSettings.photoQualityPrioritization = .quality
            
            // Bind sensor resolution safely: 12 MP vs 48 MP
            if #available(iOS 16.0, *) {
                let maxDimensions: CMVideoDimensions
                let supported = self.videoDeviceInput?.device.activeFormat.supportedMaxPhotoDimensions ?? []
                
                let target48MP = CMVideoDimensions(width: 8064, height: 6048)
                let target12MP = CMVideoDimensions(width: 4032, height: 3024)
                
                if is48MP && supported.contains(where: { $0.width == 8064 && $0.height == 6048 }) {
                    maxDimensions = target48MP
                } else if supported.contains(where: { $0.width == 4032 && $0.height == 3024 }) {
                    maxDimensions = target12MP
                } else {
                    maxDimensions = supported.max(by: { $0.width * $0.height < $1.width * $1.height }) ?? target12MP
                }
                photoSettings.maxPhotoDimensions = maxDimensions
            }
            
            if self.videoDeviceInput?.device.isFlashAvailable == true && photoOutput.supportedFlashModes.contains(.auto) {
                photoSettings.flashMode = .auto
            }
            
            photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // Record exact hardware monotonic start-of-exposure (T_SOF) before ISP/DNG compression latency
        self.lastShutterStartMachNs = AbuClockKitBridge.currentMachNanoseconds()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("CameraManager: Capture failed: \(error.localizedDescription)")
            delegate?.cameraManager(self, didFailWithError: error)
            return
        }
        
        guard let fileData = photo.fileDataRepresentation() else {
            let err = NSError(domain: "CameraManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain photo file data representation."])
            delegate?.cameraManager(self, didFailWithError: err)
            return
        }
        
        // Extract exact CMOS integration time (ExposureTime in seconds) from EXIF metadata or active device
        var exposureSeconds: Double = self.videoDeviceInput?.device.exposureDuration.seconds ?? 0.008
        if let exifDict = photo.metadata[String(kCGImagePropertyExifDictionary)] as? [String: Any],
           let exifExp = exifDict[String(kCGImagePropertyExifExposureTime)] as? Double,
           exifExp > 0.0 {
            exposureSeconds = exifExp
        }
        if exposureSeconds.isNaN || exposureSeconds <= 0.0 {
            exposureSeconds = 0.008
        }
        
        // Compute Optical Exposure Midpoint: T_mid = T_SOF + T_exposure / 2
        let sofMachNs = self.lastShutterStartMachNs > 0 ? self.lastShutterStartMachNs : AbuClockKitBridge.currentMachNanoseconds()
        let halfExpNs = UInt64(max(exposureSeconds * 0.5, 0.0) * 1_000_000_000.0)
        let midpointMachNs = sofMachNs &+ halfExpNs
        
        let extensionStr: String
        if photo.isRawPhoto {
            extensionStr = "DNG"
        } else if self.selectedFormat == "HEIF" {
            extensionStr = "HEIC"
        } else {
            extensionStr = "JPG"
        }
        
        let stamp = AbuClockKitBridge.shared.stampMonotonicNanoseconds(
            midpointMachNs,
            fileExtension: extensionStr.lowercased()
        )
        DispatchQueue.main.async {
            self.lastOpticalStamp = stamp
        }
        
        // Convert disciplined TAI ns back to UTC epoch seconds for legacy CSV compatibility (UTC = TAI - 37s)
        let taiSeconds = Double(stamp.disciplinedTaiNanoseconds) * 1.0e-9
        let timestamp = max(taiSeconds - AbuClockKitBridge.taiMinusUtcSeconds, Date().timeIntervalSince1970)
        
        // Save file to current session folder
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
              let sessionID = activeSessionID else { return }
        
        let sessionFolderURL = documentsURL.appendingPathComponent("Sessions").appendingPathComponent(sessionID)
        
        let currentCounter = photoCounter
        if !photo.isRawPhoto {
            photoCounter += 1 // Increment only for processed/jpeg companion to sync RAW/companion pairs
        }
        
        // Deterministic Abu Clock filename: <SensorID>_<HHMMSSFF>_<TAI_ns>_IMG_<Counter>.<ext>
        let token = stamp.smpteTimecode.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: ";", with: "")
        let filename = "\(stamp.sensorId)_\(token)_\(stamp.disciplinedTaiNanoseconds)_IMG_\(currentCounter).\(extensionStr)"
        let fileURL = sessionFolderURL.appendingPathComponent(filename)
        
        do {
            try fileData.write(to: fileURL)
            print("CameraManager: Saved exposure-midpoint locked photo [TC \(stamp.smpteWithSubframe) | TAI \(stamp.disciplinedTaiNanoseconds)] to: \(fileURL.path)")
            
            // Notify delegate with exact exposure-midpoint timestamp (ms) and local URL
            delegate?.cameraManager(self, didCapturePhotoAt: fileURL, timestamp: timestamp * 1000.0, filename: filename)
        } catch {
            print("CameraManager: Failed to write photo data to disk: \(error.localizedDescription)")
            delegate?.cameraManager(self, didFailWithError: error)
        }
    }
    
    // Get preview layer for live viewport overlay in SwiftUI
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let existing = self.previewLayer {
            return existing
        }
        let newLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        newLayer.videoGravity = .resizeAspect
        self.previewLayer = newLayer
        return newLayer
    }
}

// Custom view that overrides layoutSubviews to cleanly adjust layer bounds in UIKit layout cycle
class PreviewView: UIView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    
    init(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        super.init(frame: .zero)
        self.previewLayer.frame = self.bounds
        self.previewLayer.videoGravity = .resizeAspect
        self.layer.addSublayer(previewLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Safely adjust previewLayer size without triggering SwiftUI recursive invalidations
        previewLayer.frame = self.bounds
    }
}

// SwiftUI Camera Viewport Preview Wrapper
struct CameraPreviewContainer: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    func makeUIView(context: Context) -> PreviewView {
        return PreviewView(previewLayer: previewLayer)
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Leave completely empty to prevent recursive main-thread layout cycles!
    }
}
