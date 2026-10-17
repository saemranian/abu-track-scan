import Foundation
import VideoToolbox
import CoreMedia
import AVFoundation

#if canImport(Darwin)
import Darwin
#endif

class LiveVideoStreamingManager: NSObject {
    static let shared = LiveVideoStreamingManager()
    
    private var compressionSession: VTCompressionSession?
    private var pixelTransferSession: VTPixelTransferSession?
    private let encodingQueue = DispatchQueue(label: "com.abutrack.videoencoding", qos: .userInteractive)
    
    // Thread safety lock to secure properties across parallel queues
    private let sessionLock = NSLock()
    
    // POSIX BSD Socket properties for ultra-low latency streaming
    private var socketFD: Int32 = -1
    private var targetAddr = sockaddr_in()
    private var isSocketConfigured = false
    
    private var rtpSequenceNumber: UInt16 = 0
    private let ssrc: UInt32 = 0x12345678
    
    private var currentIP: String = ""
    private var currentPort: Int = 0
    private var isStreamingActive = false
    
    private var targetWidth: Int32 = 1920
    private var currentBitrate: Int = 1_500_000
    private var currentFPS: Int = 30
    private var currentDiagLevel: Int = 4
    private var currentCodec: String = "H.264"
    
    // Continuous frame counter to act as a guaranteed strictly increasing presentation time clock source
    private var frameCount: Int64 = 0
    
    // Thread-safe ring buffer mapping frame index -> AbuClock exposure-midpoint metadata
    private struct FrameClockMetadata {
        let ntpTimestamp: Double
        let taiNs: UInt64
        let bcdTimecode: UInt32
        let smpteString: String
    }
    private var frameClockRing: [Int64: FrameClockMetadata] = [:]
    
    override init() {
        super.init()
    }
    
    func startStreaming(ip: String, port: Int, width: Int32 = 1920, height: Int32 = 1080, bitrate: Int = 10_000_000, fps: Int = 30, codec: String = "H.264", diagLevel: Int = 4) {
        encodingQueue.async {
            self.sessionLock.lock()
            guard !self.isStreamingActive else {
                self.sessionLock.unlock()
                AppLogger.warning("LiveVideoStreamingManager: startStreaming ignored. Session already active.")
                return
            }
            
            AppLogger.info("LiveVideoStreamingManager: Initializing video stream targeting \(ip):\(port) with target width \(width) @ \(bitrate / 1_000) Kbps (Codec: \(codec), Diag Level: \(diagLevel))")
            
            self.currentIP = ip
            self.currentPort = port
            self.targetWidth = width
            self.currentBitrate = bitrate
            self.currentFPS = fps
            self.frameCount = 0
            self.frameClockRing.removeAll()
            self.currentCodec = codec
            self.currentDiagLevel = diagLevel
            self.isStreamingActive = true
            self.sessionLock.unlock()
            
            // 1. Setup UDP Socket
            self.setupUDPSocket(ip: ip, port: port)
            
            AppLogger.info("LiveVideoStreamingManager: UDP Socket bound. Session will lazily compile on first frame.")
        }
    }
    
    func stopStreaming() {
        encodingQueue.async {
            self.sessionLock.lock()
            guard self.isStreamingActive else {
                self.sessionLock.unlock()
                return
            }
            AppLogger.info("LiveVideoStreamingManager: Terminating active streaming session...")
            self.isStreamingActive = false
            
            let session = self.compressionSession
            self.compressionSession = nil
            self.pixelTransferSession = nil
            self.frameClockRing.removeAll()
            self.sessionLock.unlock()
            
            // Teardown VideoToolbox Session outside lock to prevent deadlocks
            if let session = session {
                VTCompressionSessionInvalidate(session)
                AppLogger.info("LiveVideoStreamingManager: VTCompressionSession invalidated successfully.")
            }
            
            // Close Socket
            self.closeSocket()
        }
    }
    
    func encodeAndStream(pixelBuffer: CVPixelBuffer, ntpTimestamp: Double, clockSample: AbuClockSample? = nil) {
        self.sessionLock.lock()
        guard self.isStreamingActive else {
            self.sessionLock.unlock()
            return
        }
        
        // LEVEL 1: Socket Only -> Skip all buffer processing, GPU cloner, and encoding!
        if self.currentDiagLevel == 1 {
            self.sessionLock.unlock()
            return
        }
        
        // Lazy compression session initialization to match exact input frame properties and aspect ratio
        if self.compressionSession == nil {
            let inputWidth = Int32(CVPixelBufferGetWidth(pixelBuffer))
            let inputHeight = Int32(CVPixelBufferGetHeight(pixelBuffer))
            
            // Calculate target size keeping 4:3 aspect ratio matching camera sensor perfectly
            let targetW = self.targetWidth > 0 ? self.targetWidth : inputWidth
            let targetH = targetW * inputHeight / inputWidth
            
            AppLogger.info("LiveVideoStreamingManager: Lazily initializing VTCompressionSession with size \(targetW)x\(targetH) (Source: \(inputWidth)x\(inputHeight))")
            
            self.sessionLock.unlock()
            self.setupCompressionSession(width: targetW, height: targetH, inputWidth: inputWidth, inputHeight: inputHeight, bitrate: self.currentBitrate, fps: self.currentFPS, codec: self.currentCodec)
            self.sessionLock.lock()
            
            guard self.compressionSession != nil else {
                self.sessionLock.unlock()
                return
            }
        }
        
        let session = self.compressionSession!
        guard let transferSession = self.pixelTransferSession else {
            self.sessionLock.unlock()
            AppLogger.error("LiveVideoStreamingManager: VTPixelTransferSession is nil.")
            return
        }
        
        guard let pool = VTCompressionSessionGetPixelBufferPool(session) else {
            self.sessionLock.unlock()
            AppLogger.error("LiveVideoStreamingManager: Failed to retrieve CVPixelBufferPool from active compression session.")
            return
        }
        
        var clonedBuffer: CVPixelBuffer?
        let poolStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &clonedBuffer)
        guard poolStatus == kCVReturnSuccess, let copy = clonedBuffer else {
            self.sessionLock.unlock()
            AppLogger.error("LiveVideoStreamingManager: Failed to allocate CVPixelBuffer from compression pool (status: \(poolStatus)).")
            return
        }
        
        // Deep copy and scale the frame directly on the GPU/VPP hardware unit to isolate memory lifecycles safely
        let transferStatus = VTPixelTransferSessionTransferImage(transferSession, from: pixelBuffer, to: copy)
        guard transferStatus == noErr else {
            self.sessionLock.unlock()
            AppLogger.error("LiveVideoStreamingManager: VTPixelTransferSessionTransferImage failed with status: \(transferStatus)")
            return
        }
        
        // LEVEL 2: GPU Copy/Scale Only -> Skip VideoToolbox encoding and network packetization!
        if self.currentDiagLevel == 2 {
            self.sessionLock.unlock()
            return
        }
        
        // Generate a strictly increasing, contiguous presentation time for the hardware encoder (90kHz ticks)
        let presentationTime = CMTime(value: self.frameCount, timescale: 90000)
        let currentFrameIndex = self.frameCount
        self.frameCount += 1
        
        // Store disciplined AbuClock exposure-midpoint sample in the ring buffer (retaining last 128 frames)
        let sample = clockSample ?? AbuClockKitBridge.shared.now()
        self.frameClockRing[currentFrameIndex] = FrameClockMetadata(
            ntpTimestamp: ntpTimestamp,
            taiNs: sample.taiNs,
            bcdTimecode: sample.bcdTimecode,
            smpteString: sample.smpteString
        )
        if self.frameClockRing.count > 128 {
            self.frameClockRing.removeValue(forKey: currentFrameIndex - 128)
        }
        
        // Pass (currentFrameIndex + 1) through sourceFrameRefCon so 0 is never nil
        let refCon = UnsafeMutableRawPointer(bitPattern: Int(currentFrameIndex) + 1)
        
        // Log frame submission details periodically for diagnostics
        if currentFrameIndex % 60 == 0 {
            let bufWidth = CVPixelBufferGetWidth(copy)
            let bufHeight = CVPixelBufferGetHeight(copy)
            AppLogger.info("LiveVideoStreamingManager: Submitting GPU-copied frame #\(currentFrameIndex) [TC \(sample.smpteString) | TAI \(sample.taiNs)] to VideoToolbox (Size: \(bufWidth)x\(bufHeight))")
        }
        
        var flags: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: copy,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: refCon,
            infoFlagsOut: &flags
        )
        self.sessionLock.unlock()
        
        if status != noErr {
            AppLogger.error("LiveVideoStreamingManager: VTCompressionSessionEncodeFrame failed for frame #\(currentFrameIndex) with status: \(status)")
        }
    }
    
    // MARK: - Private Setup Methods
    
    private func setupCompressionSession(width: Int32, height: Int32, inputWidth: Int32, inputHeight: Int32, bitrate: Int, fps: Int, codec: String) {
        AppLogger.info("LiveVideoStreamingManager: Creating VTCompressionSession (\(width)x\(height), input: \(inputWidth)x\(inputHeight), \(bitrate) bps, \(fps) fps, codec: \(codec))...")
        var session: VTCompressionSession?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        // Hardware scale NV12 input buffer configuration attributes matching target sizes
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any]
        ]
        
        let codecType = (codec == "H.265") ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: codecType,
            encoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: { (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in
                guard let refCon = outputCallbackRefCon else {
                    AppLogger.error("LiveVideoStreamingManager Callback: outputCallbackRefCon is nil!")
                    return
                }
                let manager = Unmanaged<LiveVideoStreamingManager>.fromOpaque(refCon).takeUnretainedValue()
                
                // LEVEL 3: Encoding Dry-Run -> Skip NALU parsing, packetization, and UDP transmission!
                if manager.currentDiagLevel == 3 {
                    return
                }
                
                guard status == noErr, let sampleBuffer = sampleBuffer else {
                    AppLogger.error("LiveVideoStreamingManager Callback: Encoder returned error status: \(status) or empty buffer.")
                    return
                }
                
                // Retrieve FrameClockMetadata from ring buffer via frame index
                let frameIdx = Int64(Int(bitPattern: sourceFrameRefCon) - 1)
                manager.sessionLock.lock()
                let meta = manager.frameClockRing.removeValue(forKey: frameIdx)
                manager.sessionLock.unlock()
                
                let fallbackSample = AbuClockKitBridge.shared.now()
                let ntpTime = meta?.ntpTimestamp ?? fallbackSample.utcSeconds
                let taiNs = meta?.taiNs ?? fallbackSample.taiNs
                let bcdTc = meta?.bcdTimecode ?? fallbackSample.bcdTimecode
                
                // Process and packetize the sample buffer synchronously while it's guaranteed valid
                manager.processEncodedFrame(sampleBuffer: sampleBuffer, ntpTimestamp: ntpTime, taiNs: taiNs, bcdTimecode: bcdTc)
            },
            refcon: selfPtr,
            compressionSessionOut: &session
        )
        
        guard status == noErr, let createdSession = session else {
            AppLogger.critical("LiveVideoStreamingManager: Failed to create VTCompressionSession: status \(status)")
            return
        }
        
        AppLogger.info("LiveVideoStreamingManager: Session created successfully. Setting properties...")
        
        // Configure Hardware encoding options for ultra low latency virtual production
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        if codec == "H.265" {
            VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        } else {
            VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        }
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps)) // I-frame every 1s
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse) // No B-Frames
        
        // Start session
        VTCompressionSessionPrepareToEncodeFrames(createdSession)
        
        // Create VTPixelTransferSession for GPU-accelerated frame copying and scaling
        var transferSession: VTPixelTransferSession?
        let transferStatus = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transferSession)
        if transferStatus == noErr {
            AppLogger.info("LiveVideoStreamingManager: VTPixelTransferSession created successfully.")
        } else {
            AppLogger.error("LiveVideoStreamingManager: Failed to create VTPixelTransferSession with status: \(transferStatus)")
        }
        
        // Save to instance variable under lock
        sessionLock.lock()
        if let oldSession = self.compressionSession {
            VTCompressionSessionInvalidate(oldSession)
        }
        self.compressionSession = createdSession
        self.pixelTransferSession = transferSession
        sessionLock.unlock()
        
        AppLogger.info("LiveVideoStreamingManager: Hardware compression session fully prepared and active.")
    }
    
    private func setupUDPSocket(ip: String, port: Int) {
        AppLogger.info("LiveVideoStreamingManager: Binding UDP streaming socket targeting \(ip):\(port)...")
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            AppLogger.error("LiveVideoStreamingManager: Failed to create local BSD socket.")
            return
        }
        
        // Enable SO_BROADCAST in case we stream to subnet
        var broadcastEnable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))
        
        // Prepare target sockaddr_in
        var addr = sockaddr_in()
        #if os(iOS) || os(macOS)
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(UInt16(port))
        
        let resolved = inet_addr(ip)
        if resolved == 0xffffffff && ip != "255.255.255.255" {
            AppLogger.error("LiveVideoStreamingManager: Invalid target IP parsed: \(ip)")
            close(fd)
            return
        }
        addr.sin_addr.s_addr = resolved
        
        // Save under lock
        sessionLock.lock()
        if self.socketFD >= 0 {
            close(self.socketFD)
        }
        self.socketFD = fd
        self.targetAddr = addr
        self.isSocketConfigured = true
        sessionLock.unlock()
        
        AppLogger.info("LiveVideoStreamingManager: Bound BSD UDP socket successfully.")
    }
    
    private func closeSocket() {
        sessionLock.lock()
        let fd = self.socketFD
        self.socketFD = -1
        self.isSocketConfigured = false
        sessionLock.unlock()
        
        if fd >= 0 {
            close(fd)
            AppLogger.info("LiveVideoStreamingManager: Bound BSD UDP socket closed cleanly.")
        }
    }
    
    // MARK: - Frame Processing & Packetization (RFC 6184 / RFC 7798 RTP + RFC 5285 AbuClock Extension)
    
    private func buildRTPHeader(marker: Bool, rtpTimestamp: UInt32, includeAbuClockExtension: Bool, bcdTimecode: UInt32, taiNs: UInt64) -> Data {
        var packet = Data()
        packet.reserveCapacity(includeAbuClockExtension ? 32 : 12)
        
        // 1. RTP Fixed Header (12 bytes)
        // Byte 0: V=2 (0x80), P=0, X=includeAbuClockExtension (0x10), CC=0
        packet.append(includeAbuClockExtension ? 0x90 : 0x80)
        // Byte 1: Payload Type = 96 (Dynamic H.264/HEVC), Marker Bit set on final packet of frame
        packet.append(UInt8(96 | (marker ? 0x80 : 0x00)))
        
        // Bytes 2..3: Sequence Number (UInt16 BE)
        packet.append(UInt8((rtpSequenceNumber >> 8) & 0xFF))
        packet.append(UInt8(rtpSequenceNumber & 0xFF))
        rtpSequenceNumber = rtpSequenceNumber.addingReportingOverflow(1).partialValue
        
        // Bytes 4..7: 90kHz RTP Timestamp locked to AbuClock TAI Exposure Midpoint (UInt32 BE)
        packet.append(UInt8((rtpTimestamp >> 24) & 0xFF))
        packet.append(UInt8((rtpTimestamp >> 16) & 0xFF))
        packet.append(UInt8((rtpTimestamp >> 8) & 0xFF))
        packet.append(UInt8(rtpTimestamp & 0xFF))
        
        // Bytes 8..11: SSRC (UInt32 BE)
        packet.append(UInt8((ssrc >> 24) & 0xFF))
        packet.append(UInt8((ssrc >> 16) & 0xFF))
        packet.append(UInt8((ssrc >> 8) & 0xFF))
        packet.append(UInt8(ssrc & 0xFF))
        
        // 2. Optional RFC 5285 One-Byte RTP Header Extension (0xBEDE, 4 words = 16 bytes payload)
        if includeAbuClockExtension {
            // Profile-specific identifier: 0xBEDE (RFC 5285 One-Byte Header)
            packet.append(0xBE)
            packet.append(0xDE)
            // Length in 32-bit words: 4 (16 bytes)
            packet.append(0x00)
            packet.append(0x04)
            
            // Extension Element #1: ID=1, L=3 (4 bytes): 32-bit SMPTE ST 12-1 BCD Timecode
            packet.append(0x13)
            packet.append(UInt8((bcdTimecode >> 24) & 0xFF))
            packet.append(UInt8((bcdTimecode >> 16) & 0xFF))
            packet.append(UInt8((bcdTimecode >> 8) & 0xFF))
            packet.append(UInt8(bcdTimecode & 0xFF))
            
            // Extension Element #2: ID=2, L=7 (8 bytes): 64-bit TAI Nanoseconds (Exposure Midpoint)
            packet.append(0x27)
            for shift in stride(from: 56, through: 0, by: -8) {
                packet.append(UInt8((taiNs >> shift) & 0xFF))
            }
            
            // 2 bytes zero padding to align to 32-bit word boundary (5 + 9 + 2 = 16 bytes)
            packet.append(0x00)
            packet.append(0x00)
        }
        
        return packet
    }
    
    private func processEncodedFrame(sampleBuffer: CMSampleBuffer, ntpTimestamp: Double, taiNs: UInt64 = 0, bcdTimecode: UInt32 = 0) {
        self.sessionLock.lock()
        let socketReady = self.isSocketConfigured && self.socketFD >= 0
        self.sessionLock.unlock()
        
        guard socketReady else {
            return
        }
        
        // 1. Check if it's a keyframe (I-Frame) in 100% native CoreFoundation to prevent Swift array bridging crashes
        var isKeyframe = false
        if let attachmentsCF = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
           CFArrayGetCount(attachmentsCF) > 0 {
            if let attachmentRef = CFArrayGetValueAtIndex(attachmentsCF, 0) {
                let attachment = unsafeBitCast(attachmentRef, to: CFDictionary.self)
                let key = Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()
                if let notSyncRef = CFDictionaryGetValue(attachment, key) {
                    let notSyncCF = unsafeBitCast(notSyncRef, to: CFBoolean.self)
                    isKeyframe = !CFBooleanGetValue(notSyncCF)
                } else {
                    isKeyframe = true
                }
            }
        } else {
            isKeyframe = true
        }
        
        // 2. Extract SPS / PPS / VPS Parameter Sets on Keyframes to initialize standard decoders mid-stream
        if isKeyframe {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                var paramSetCount = 0
                let isHEVC = (self.currentCodec == "H.265")
                let countStatus: OSStatus
                
                if isHEVC {
                    countStatus = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                        formatDesc,
                        parameterSetIndex: 0,
                        parameterSetPointerOut: nil,
                        parameterSetSizeOut: nil,
                        parameterSetCountOut: &paramSetCount,
                        nalUnitHeaderLengthOut: nil
                    )
                } else {
                    countStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                        formatDesc,
                        parameterSetIndex: 0,
                        parameterSetPointerOut: nil,
                        parameterSetSizeOut: nil,
                        parameterSetCountOut: &paramSetCount,
                        nalUnitHeaderLengthOut: nil
                    )
                }
                
                guard countStatus == noErr else {
                    AppLogger.error("LiveVideoStreamingManager processEncodedFrame: Failed to get parameter set count. Status: \(countStatus)")
                    return
                }
                
                for i in 0..<paramSetCount {
                    var paramPtr: UnsafePointer<UInt8>? = nil
                    var paramSize = 0
                    let status: OSStatus
                    
                    if isHEVC {
                        status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                            formatDesc,
                            parameterSetIndex: i,
                            parameterSetPointerOut: &paramPtr,
                            parameterSetSizeOut: &paramSize,
                            parameterSetCountOut: nil,
                            nalUnitHeaderLengthOut: nil
                        )
                    } else {
                        status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                            formatDesc,
                            parameterSetIndex: i,
                            parameterSetPointerOut: &paramPtr,
                            parameterSetSizeOut: &paramSize,
                            parameterSetCountOut: nil,
                            nalUnitHeaderLengthOut: nil
                        )
                    }
                    
                    if status == noErr, let ptr = paramPtr, paramSize > 0 {
                        let naluData = Data(bytes: ptr, count: paramSize)
                        sendNALUnit(naluData, ntpTimestamp: ntpTimestamp, taiNs: taiNs, bcdTimecode: bcdTimecode, isLast: false)
                    } else {
                        AppLogger.error("LiveVideoStreamingManager processEncodedFrame: parameter set failed at index \(i) with status: \(status)")
                    }
                }
            }
        }
        
        // 3. Process NAL Units from AVCC Block Buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        let totalLength = CMBlockBufferGetDataLength(blockBuffer)
        guard totalLength > 0 else {
            return
        }
        
        // Safely copy data bytes to a contiguous buffer to prevent memory access issues on non-contiguous memory blocks
        var buffer = Data(count: totalLength)
        let status = buffer.withUnsafeMutableBytes { (bufferPtr: UnsafeMutableRawBufferPointer) -> OSStatus in
            guard let baseAddress = bufferPtr.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: totalLength, destination: baseAddress)
        }
        
        guard status == noErr else {
            AppLogger.error("LiveVideoStreamingManager processEncodedFrame: CMBlockBufferCopyDataBytes failed with status: \(status)")
            return
        }
        
        buffer.withUnsafeBytes { (bytesPtr: UnsafeRawBufferPointer) in
            guard let basePointer = bytesPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var offset = 0
            while offset + 4 <= totalLength {
                // AVCC format: NALU is prefixed by 4-byte big-endian length field
                var naluLength: UInt32 = 0
                memcpy(&naluLength, basePointer + offset, 4)
                naluLength = CFSwapInt32BigToHost(naluLength)
                
                offset += 4
                
                guard naluLength > 0 else { continue }
                
                if offset + Int(naluLength) <= totalLength {
                    let naluData = buffer.subdata(in: offset..<(offset + Int(naluLength)))
                    let isLastNalu = (offset + Int(naluLength) >= totalLength)
                    sendNALUnit(naluData, ntpTimestamp: ntpTimestamp, taiNs: taiNs, bcdTimecode: bcdTimecode, isLast: isLastNalu)
                } else {
                    break // Out of bounds NALU length!
                }
                offset += Int(naluLength)
            }
        }
    }
    
    private func sendNALUnit(_ nalu: Data, ntpTimestamp: Double, taiNs: UInt64 = 0, bcdTimecode: UInt32 = 0, isLast: Bool) {
        guard !nalu.isEmpty else { return }
        
        // Scaled AbuClock TAI exposure-midpoint timestamp in 90kHz ticks for accurate UE Composure & DesktopSync frame alignment
        let timeSec = taiNs > 0 ? (Double(taiNs) / 1_000_000_000.0) : ntpTimestamp
        let rtpTimestamp = UInt32((timeSec * 90000.0).truncatingRemainder(dividingBy: 4294967296.0))
        let maxPayloadSize = 1380 // Safe Ethernet MTU Size (leaving room for 20-byte RFC 5285 AbuClock extension)
        
        let isHEVC = (self.currentCodec == "H.265")
        
        if isHEVC {
            // H.265 HEVC RTP Packetization (RFC 7798)
            let naluHeader1 = nalu[0]
            let naluHeader2 = nalu[1]
            let naluType = (naluHeader1 >> 1) & 0x3F
            
            // Periodic check to log key frame headers (VPS=32, SPS=33, PPS=34)
            if naluType == 32 || naluType == 33 || naluType == 34 {
                AppLogger.info("LiveVideoStreamingManager: Transmitting H.265 parameter set type \(naluType), size \(nalu.count) bytes.")
            }
            
            if nalu.count <= maxPayloadSize {
                var packet = buildRTPHeader(
                    marker: isLast,
                    rtpTimestamp: rtpTimestamp,
                    includeAbuClockExtension: isLast && taiNs > 0,
                    bcdTimecode: bcdTimecode,
                    taiNs: taiNs
                )
                
                // 2. Payload (Full H.265 NALU)
                packet.append(nalu)
                
                let rtpPacket = packet
                encodingQueue.async { [weak self] in
                    self?.sendPacket(rtpPacket)
                }
            } else {
                // Fragment large H.265 NALU using FU Packets (Type 49)
                let fuIndicator1 = (naluHeader1 & 0x81) | (49 << 1)
                let fuIndicator2 = naluHeader2
                
                let payloadData = nalu.subdata(in: 2..<nalu.count)
                let totalPayloadSize = payloadData.count
                var bytesSent = 0
                
                while bytesSent < totalPayloadSize {
                    let isFirstFragment = (bytesSent == 0)
                    let isLastFragment = (bytesSent + maxPayloadSize >= totalPayloadSize)
                    let chunkSize = min(maxPayloadSize, totalPayloadSize - bytesSent)
                    let markerBit = isLast && isLastFragment
                    
                    var packet = buildRTPHeader(
                        marker: markerBit,
                        rtpTimestamp: rtpTimestamp,
                        includeAbuClockExtension: markerBit && taiNs > 0,
                        bcdTimecode: bcdTimecode,
                        taiNs: taiNs
                    )
                    
                    // 2. FU Indicator (2 bytes)
                    packet.append(fuIndicator1)
                    packet.append(fuIndicator2)
                    
                    // 3. FU Header Byte (S | E | Type)
                    let sBit: UInt8 = isFirstFragment ? 0x80 : 0x00
                    let eBit: UInt8 = isLastFragment ? 0x40 : 0x00
                    let fuHeader = sBit | eBit | naluType
                    packet.append(fuHeader)
                    
                    // 4. Fragment Payload chunk
                    let chunk = payloadData.subdata(in: bytesSent..<(bytesSent + chunkSize))
                    packet.append(chunk)
                    
                    let rtpPacket = packet
                    encodingQueue.async { [weak self] in
                        self?.sendPacket(rtpPacket)
                    }
                    
                    bytesSent += chunkSize
                }
            }
        } else {
            // H.264 RTP Packetization (RFC 6184)
            let naluHeader = nalu[0]
            let naluType = naluHeader & 0x1F
            
            // Periodic check to log key frame headers
            if naluType == 7 || naluType == 8 {
                AppLogger.info("LiveVideoStreamingManager: Transmitting H.264 parameter set type \(naluType), size \(nalu.count) bytes.")
            }
            
            if nalu.count <= maxPayloadSize {
                // Send as a single RTP packet (RFC 6184)
                var packet = buildRTPHeader(
                    marker: isLast,
                    rtpTimestamp: rtpTimestamp,
                    includeAbuClockExtension: isLast && taiNs > 0,
                    bcdTimecode: bcdTimecode,
                    taiNs: taiNs
                )
                
                // 2. Payload (Full NALU)
                packet.append(nalu)
                
                let rtpPacket = packet
                encodingQueue.async { [weak self] in
                    self?.sendPacket(rtpPacket)
                }
            } else {
                // Fragment large NALU using FU-A Packets (Type 28)
                let nri = naluHeader & 0x60
                let fuIndicator = nri | 28
                
                let payloadData = nalu.subdata(in: 1..<nalu.count)
                let totalPayloadSize = payloadData.count
                var bytesSent = 0
                
                while bytesSent < totalPayloadSize {
                    let isFirstFragment = (bytesSent == 0)
                    let isLastFragment = (bytesSent + maxPayloadSize >= totalPayloadSize)
                    let chunkSize = min(maxPayloadSize, totalPayloadSize - bytesSent)
                    let markerBit = isLast && isLastFragment
                    
                    var packet = buildRTPHeader(
                        marker: markerBit,
                        rtpTimestamp: rtpTimestamp,
                        includeAbuClockExtension: markerBit && taiNs > 0,
                        bcdTimecode: bcdTimecode,
                        taiNs: taiNs
                    )
                    
                    // 2. FU-A Indicator Byte
                    packet.append(fuIndicator)
                    
                    // 3. FU-A Header Byte (S | E | R | Type)
                    let sBit: UInt8 = isFirstFragment ? 0x80 : 0x00
                    let eBit: UInt8 = isLastFragment ? 0x40 : 0x00
                    let fuHeader = sBit | eBit | naluType
                    packet.append(fuHeader)
                    
                    // 4. Fragment Payload chunk
                    let chunk = payloadData.subdata(in: bytesSent..<(bytesSent + chunkSize))
                    packet.append(chunk)
                    
                    let rtpPacket = packet
                    encodingQueue.async { [weak self] in
                        self?.sendPacket(rtpPacket)
                    }
                    
                    bytesSent += chunkSize
                }
            }
        }
    }
    
    private func sendPacket(_ data: Data) {
        self.sessionLock.lock()
        let fd = self.socketFD
        var addr = self.targetAddr
        let ready = self.isSocketConfigured && fd >= 0
        self.sessionLock.unlock()
        
        guard ready else { return }
        
        let count = data.count
        _ = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                data.withUnsafeBytes { dataBytes in
                    sendto(fd, dataBytes.baseAddress, count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
    
    deinit {
        closeSocket()
    }
}
