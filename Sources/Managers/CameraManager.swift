import Foundation
import AVFoundation
import UIKit
import SwiftUI

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
    
    override init() {
        super.init()
    }
    
    func setupCamera(completion: @escaping (Bool) -> Void) {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo // Maximum resolution
            
            // 1. Find best Dual/Triple/Wide-angle Back Camera
            let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
            
            guard let videoDevice = deviceDiscoverySession.devices.first else {
                print("CameraManager: No back camera found")
                self.captureSession.commitConfiguration()
                completion(false)
                return
            }
            
            // Configure hardware settings for absolute best clarity
            do {
                try videoDevice.lockForConfiguration()
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
                if photoOutput.supportedQualityPrioritizations.contains(.quality) {
                    photoOutput.maxPhotoQualityPrioritization = .quality // DSLR-quality Deep Fusion/Smart HDR processing
                }
                
                if #available(iOS 16.0, *) {
                    // Query the maximum dimensions supported by the active format to avoid startup exception crash
                    if let maxDim = photoOutput.supportedPhotoMaxDimensions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                        photoOutput.maxPhotoDimensions = maxDim
                    }
                }
            } else {
                print("CameraManager: Cannot add photo output")
                self.captureSession.commitConfiguration()
                completion(false)
                return
            }
            
            self.captureSession.commitConfiguration()
            completion(true)
        }
    }
    
    func startSession(sessionID: String) {
        self.activeSessionID = sessionID
        self.photoCounter = 1255 // Reset photo count index per run
        
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                print("CameraManager: Capture session started running")
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                print("CameraManager: Capture session stopped running")
            }
        }
        self.activeSessionID = nil
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
                    let duration = CMTime(seconds: shutterSpeed, preferredTimescale: 1000000)
                    device.setExposureModeCustom(duration: duration, iso: Float(iso), completionHandler: nil)
                }
                
                // 2. White Balance temperature settings (wbTemperature = 0.0 is automatic)
                if wbTemperature == 0.0 {
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                } else {
                    let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(wbTemperature), tint: 0.0)
                    let gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                    
                    let maxGain = device.maxWhiteBalanceGain
                    let clampedGains = AVCaptureDevice.WhiteBalanceGains(
                        redGain: max(1.0, min(maxGain, gains.redGain)),
                        greenGain: max(1.0, min(maxGain, gains.greenGain)),
                        blueGain: max(1.0, min(maxGain, gains.blueGain))
                    )
                    device.setWhiteBalanceModeLocked(with: clampedGains, completionHandler: nil)
                }
                
                device.unlockForConfiguration()
            } catch {
                print("CameraManager: Failed to configure exposure/WB parameters: \(error)")
            }
        }
    }
    
    // Sets active physical lens and digital zoom factor (from 0.5x to 25.0x or hardware limits)
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
            
            var photoSettings = AVCapturePhotoSettings()
            
            // Resolve format constraints: DNG (RAW), HEIF, JPG
            if format == "DNG" && !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty {
                let firstRawType = photoOutput.availableRawPhotoPixelFormatTypes.first!
                let rawFormatType: OSType
                if let nsNum = firstRawType as? NSNumber {
                    rawFormatType = nsNum.uint32Value
                } else {
                    rawFormatType = firstRawType as! OSType
                }
                photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormatType, processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else if format == "HEIF" && photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
            
            // Set high-resolution options safely
            photoSettings.isHighResolutionPhotoEnabled = true
            if photoOutput.supportedQualityPrioritizations.contains(.quality) {
                photoSettings.photoQualityPrioritization = .quality
            }
            
            // Bind sensor resolution safely: 12 MP vs 48 MP
            if #available(iOS 16.0, *) {
                let maxDimensions: CMVideoDimensions
                let supported = photoOutput.supportedPhotoMaxDimensions
                
                let target48MP = CMVideoDimensions(width: 8064, height: 6048)
                let target12MP = CMVideoDimensions(width: 4032, height: 3024)
                
                if is48MP && supported.contains(where: { $0.width == 8064 && $0.height == 6048 }) {
                    maxDimensions = target48MP
                } else if supported.contains(where: { $0.width == 4032 && $0.height == 3024 }) {
                    maxDimensions = target12MP
                } else {
                    maxDimensions = supported.max(by: { $0.width * $0.height < $1.width * $1.height }) ?? CMVideoDimensions(width: 4032, height: 3024)
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
        
        let timestamp = Date().timeIntervalSince1970 // Microsecond-accurate time
        
        // Save file to current session folder
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
              let sessionID = activeSessionID else { return }
        
        let sessionFolderURL = documentsURL.appendingPathComponent("Sessions").appendingPathComponent(sessionID)
        
        // Build filename matches structure: YYYY_MM_DD_HH_MM_IMG_XXXX.JPG
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd_HH_mm"
        let datePrefix = formatter.string(from: Date())
        let filename = "\(datePrefix)_IMG_\(photoCounter).JPG"
        photoCounter += 1
        
        let fileURL = sessionFolderURL.appendingPathComponent(filename)
        
        do {
            try fileData.write(to: fileURL)
            print("CameraManager: Successfully saved high-res photo to: \(fileURL.path)")
            
            // Notify delegate with exact timestamp and local URL
            delegate?.cameraManager(self, didCapturePhotoAt: fileURL, timestamp: timestamp * 1000.0, filename: filename)
        } catch {
            print("CameraManager: Failed to write photo data to disk: \(error.localizedDescription)")
            delegate?.cameraManager(self, didFailWithError: error)
        }
    }
    
    // Get preview layer for live viewport overlay in SwiftUI
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        let previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        return previewLayer
    }
}

// SwiftUI Camera Viewport Preview Wrapper
struct CameraPreviewContainer: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            self.previewLayer.frame = uiView.bounds
        }
    }
}
