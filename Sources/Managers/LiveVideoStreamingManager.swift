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
    
    // Continuous frame counter to act as a guaranteed strictly increasing presentation time clock source
    private var frameCount: Int64 = 0
    
    override init() {
        super.init()
    }
    
    func startStreaming(ip: String, port: Int, width: Int32 = 1920, height: Int32 = 1080, bitrate: Int = 10_000_000, fps: Int = 30) {
        encodingQueue.async {
            self.sessionLock.lock()
            guard !self.isStreamingActive else {
                self.sessionLock.unlock()
                AppLogger.warning("LiveVideoStreamingManager: startStreaming ignored. Session already active.")
                return
            }
            
            AppLogger.info("LiveVideoStreamingManager: Initializing video stream targeting \(ip):\(port) with target width \(width) @ \(bitrate / 1_000) Kbps")
            
            self.currentIP = ip
            self.currentPort = port
            self.targetWidth = width
            self.currentBitrate = bitrate
            self.currentFPS = fps
            self.frameCount = 0
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
    
    private func copyPixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(src)
        let height = CVPixelBufferGetHeight(src)
        let format = CVPixelBufferGetPixelFormatType(src)
        
        var dst: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any]
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            attrs as CFDictionary,
            &dst
        )
        
        guard status == kCVReturnSuccess, let copy = dst else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
        }
        
        let planeCount = CVPixelBufferGetPlaneCount(src)
        if planeCount > 0 {
            for plane in 0..<planeCount {
                guard let srcAddr = CVPixelBufferGetBaseAddressOfPlane(src, plane),
                      let dstAddr = CVPixelBufferGetBaseAddressOfPlane(copy, plane) else {
                    continue
                }
                let heightPlane = CVPixelBufferGetHeightOfPlane(src, plane)
                let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(src, plane)
                let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(copy, plane)
                
                if srcBytesPerRow == dstBytesPerRow {
                    let size = srcBytesPerRow * heightPlane
                    memcpy(dstAddr, srcAddr, size)
                } else {
                    for y in 0..<heightPlane {
                        let srcRow = srcAddr + y * srcBytesPerRow
                        let dstRow = dstAddr + y * dstBytesPerRow
                        memcpy(dstRow, srcRow, min(srcBytesPerRow, dstBytesPerRow))
                    }
                }
            }
        } else {
            guard let srcAddr = CVPixelBufferGetBaseAddress(src),
                  let dstAddr = CVPixelBufferGetBaseAddress(copy) else {
                return nil
            }
            let height = CVPixelBufferGetHeight(src)
            let srcBytesPerRow = CVPixelBufferGetBytesPerRow(src)
            let dstBytesPerRow = CVPixelBufferGetBytesPerRow(copy)
            
            if srcBytesPerRow == dstBytesPerRow {
                let size = srcBytesPerRow * height
                memcpy(dstAddr, srcAddr, size)
            } else {
                for y in 0..<height {
                    let srcRow = srcAddr + y * srcBytesPerRow
                    let dstRow = dstAddr + y * dstBytesPerRow
                    memcpy(dstRow, srcRow, min(srcBytesPerRow, dstBytesPerRow))
                }
            }
        }
        
        CVBufferPropagateAttachments(src, copy)
        return copy
    }

    func encodeAndStream(pixelBuffer: CVPixelBuffer, ntpTimestamp: Double) {
        self.sessionLock.lock()
        guard self.isStreamingActive else {
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
            self.setupCompressionSession(width: targetW, height: targetH, inputWidth: inputWidth, inputHeight: inputHeight, bitrate: self.currentBitrate, fps: self.currentFPS)
            self.sessionLock.lock()
            
            guard self.compressionSession != nil else {
                self.sessionLock.unlock()
                return
            }
        }
        
        let session = self.compressionSession!
        
        // Safely copy the pixel buffer to decouple its memory lifetime from ARKit's aggressive frame recycling pool
        guard let copiedBuffer = self.copyPixelBuffer(pixelBuffer) else {
            self.sessionLock.unlock()
            AppLogger.error("LiveVideoStreamingManager: Failed to clone CVPixelBuffer for encoding.")
            return
        }
        
        // Generate a strictly increasing, contiguous presentation time for the hardware encoder (90kHz ticks)
        let presentationTime = CMTime(value: self.frameCount, timescale: 90000)
        let currentFrameIndex = self.frameCount
        self.frameCount += 1
        
        // Pass the precise double NTP timestamp through sourceFrameRefCon
        let timestampUs = Int(ntpTimestamp * 1_000_000.0)
        let refCon = UnsafeMutableRawPointer(bitPattern: timestampUs)
        
        // Log frame submission details periodically for diagnostics
        if currentFrameIndex % 60 == 0 {
            let bufWidth = CVPixelBufferGetWidth(copiedBuffer)
            let bufHeight = CVPixelBufferGetHeight(copiedBuffer)
            AppLogger.info("LiveVideoStreamingManager: Submitting frame #\(currentFrameIndex) to VideoToolbox (Active PixelBuffer: \(bufWidth)x\(bufHeight))")
        }
        
        var flags: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: copiedBuffer,
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
    
    private func setupCompressionSession(width: Int32, height: Int32, inputWidth: Int32, inputHeight: Int32, bitrate: Int, fps: Int) {
        AppLogger.info("LiveVideoStreamingManager: Creating VTCompressionSession (\(width)x\(height), input: \(inputWidth)x\(inputHeight), \(bitrate) bps, \(fps) fps)...")
        var session: VTCompressionSession?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        // Hardware scale NV12 input buffer configuration attributes
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: inputWidth,
            kCVPixelBufferHeightKey: inputHeight
        ]
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: { (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in
                guard let refCon = outputCallbackRefCon else {
                    AppLogger.error("LiveVideoStreamingManager Callback: outputCallbackRefCon is nil!")
                    return
                }
                let manager = Unmanaged<LiveVideoStreamingManager>.fromOpaque(refCon).takeUnretainedValue()
                
                guard status == noErr, let sampleBuffer = sampleBuffer else {
                    AppLogger.error("LiveVideoStreamingManager Callback: Encoder returned error status: \(status) or empty buffer.")
                    return
                }
                
                // Decode the NTP timestamp from the source reference pointer
                let timestampUs = Int(bitPattern: sourceFrameRefCon)
                let originalNtpTime = Double(timestampUs) / 1_000_000.0
                
                // Process and packetize the sample buffer synchronously while it's guaranteed valid
                manager.processEncodedFrame(sampleBuffer: sampleBuffer, ntpTimestamp: originalNtpTime)
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
        // Main profile is universally supported across all iOS hardware models and resolutions
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps)) // I-frame every 1s
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse) // No B-Frames
        
        // Start session
        VTCompressionSessionPrepareToEncodeFrames(createdSession)
        
        // Save to instance variable under lock
        sessionLock.lock()
        if let oldSession = self.compressionSession {
            VTCompressionSessionInvalidate(oldSession)
        }
        self.compressionSession = createdSession
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
    
    // MARK: - Frame Processing & Packetization (RFC 6184 H.264 RTP)
    
    private func processEncodedFrame(sampleBuffer: CMSampleBuffer, ntpTimestamp: Double) {
        self.sessionLock.lock()
        let socketReady = self.isSocketConfigured && self.socketFD >= 0
        self.sessionLock.unlock()
        
        guard socketReady else {
            AppLogger.warning("LiveVideoStreamingManager: processEncodedFrame ignored. Socket not ready.")
            return
        }
        
        // 1. Check if it's a keyframe (I-Frame)
        var isKeyframe = false
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [CFDictionary],
           let attachment = attachments.first {
            let notSync = CFDictionaryGetValue(attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
            isKeyframe = (notSync == nil)
        }
        
        // 2. Extract SPS / PPS Parameter Sets on Keyframes to initialize standard decoders mid-stream
        if isKeyframe, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var paramSetCount = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &paramSetCount, nalUnitHeaderLengthOut: nil)
            
            AppLogger.info("LiveVideoStreamingManager: Keyframe generated. Extracting \(paramSetCount) Parameter Sets (SPS/PPS)...")
            
            for i in 0..<paramSetCount {
                var paramPtr: UnsafePointer<UInt8>?
                var paramSize = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: i, parameterSetPointerOut: &paramPtr, parameterSetSizeOut: &paramSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                
                if let ptr = paramPtr {
                    let naluData = Data(bytes: ptr, count: paramSize)
                    sendNALUnit(naluData, ntpTimestamp: ntpTimestamp, isLast: false)
                }
            }
        }
        
        // 3. Process NAL Units from AVCC Block Buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let totalLength = CMBlockBufferGetDataLength(blockBuffer)
        guard totalLength > 0 else { return }
        
        // Safely copy data bytes to a contiguous buffer to prevent memory access issues on non-contiguous memory blocks
        var buffer = Data(count: totalLength)
        let status = buffer.withUnsafeMutableBytes { (bufferPtr: UnsafeMutableRawBufferPointer) -> OSStatus in
            guard let baseAddress = bufferPtr.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: totalLength, destination: baseAddress)
        }
        
        guard status == noErr else {
            AppLogger.error("LiveVideoStreamingManager: CMBlockBufferCopyDataBytes failed with status: \(status)")
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
                    sendNALUnit(naluData, ntpTimestamp: ntpTimestamp, isLast: isLastNalu)
                } else {
                    AppLogger.warning("LiveVideoStreamingManager: Aborting AVCC loop. Out of bounds slice size detected.")
                    break // Out of bounds NALU length!
                }
                offset += Int(naluLength)
            }
        }
    }
    
    private func sendNALUnit(_ nalu: Data, ntpTimestamp: Double, isLast: Bool) {
        guard !nalu.isEmpty else { return }
        
        // Scaled NTP Shutter timestamp in 90kHz ticks for accurate UE Composure frame alignment
        let rtpTimestamp = UInt32(ntpTimestamp.truncatingRemainder(dividingBy: 4294967296.0) * 90000.0)
        let maxPayloadSize = 1400 // Safe Ethernet MTU Size to prevent packet fragmentation
        
        let naluHeader = nalu[0]
        let naluType = naluHeader & 0x1F
        
        // Periodic check to log key frame headers
        if naluType == 7 || naluType == 8 {
            AppLogger.info("LiveVideoStreamingManager: Transmitting parameter set type \(naluType), size \(nalu.count) bytes.")
        }
        
        if nalu.count <= maxPayloadSize {
            // Send as a single RTP packet (RFC 6184)
            var packet = Data()
            
            // 1. RTP Header (12 bytes)
            packet.append(0x80) // V=2, P=0, X=0, CC=0
            packet.append(UInt8(96 | (isLast ? 0x80 : 0x00))) // Payload Type = 96 (Dynamic H.264), Marker Bit set on final packet
            
            var seqBig = rtpSequenceNumber.bigEndian
            packet.append(contentsOf: withUnsafeBytes(of: &seqBig) { Array($0) })
            rtpSequenceNumber = rtpSequenceNumber.addingReportingOverflow(1).partialValue
            
            var tsBig = rtpTimestamp.bigEndian
            packet.append(contentsOf: withUnsafeBytes(of: &tsBig) { Array($0) })
            
            var ssrcBig = ssrc.bigEndian
            packet.append(contentsOf: withUnsafeBytes(of: &ssrcBig) { Array($0) })
            
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
                
                var packet = Data()
                
                // 1. RTP Header (12 bytes)
                packet.append(0x80)
                packet.append(UInt8(96 | ((isLast && isLastFragment) ? 0x80 : 0x00))) // Marker bit set on final fragment of final frame NALU
                
                var seqBig = rtpSequenceNumber.bigEndian
                packet.append(contentsOf: withUnsafeBytes(of: &seqBig) { Array($0) })
                rtpSequenceNumber = rtpSequenceNumber.addingReportingOverflow(1).partialValue
                
                var tsBig = rtpTimestamp.bigEndian
                packet.append(contentsOf: withUnsafeBytes(of: &tsBig) { Array($0) })
                
                var ssrcBig = ssrc.bigEndian
                packet.append(contentsOf: withUnsafeBytes(of: &ssrcBig) { Array($0) })
                
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
