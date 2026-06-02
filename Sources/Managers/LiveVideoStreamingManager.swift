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
                return
            }
            
            print("Video Streaming: Initializing stream to \(ip):\(port) with resolution \(width)x\(height) @ \(bitrate / 1_000_000) Mbps")
            
            self.currentIP = ip
            self.currentPort = port
            self.frameCount = 0
            self.isStreamingActive = true
            self.sessionLock.unlock()
            
            // 1. Setup UDP Socket
            self.setupUDPSocket(ip: ip, port: port)
            
            // 2. Setup VideoToolbox Compression Session
            self.setupCompressionSession(width: width, height: height, bitrate: bitrate, fps: fps)
            
            print("Video Streaming: Stream successfully active.")
        }
    }
    
    func stopStreaming() {
        encodingQueue.async {
            self.sessionLock.lock()
            guard self.isStreamingActive else {
                self.sessionLock.unlock()
                return
            }
            print("Video Streaming: Terminating streaming sessions.")
            self.isStreamingActive = false
            
            let session = self.compressionSession
            self.compressionSession = nil
            self.sessionLock.unlock()
            
            // Teardown VideoToolbox Session outside lock to prevent deadlocks
            if let session = session {
                VTCompressionSessionInvalidate(session)
            }
            
            // Close Socket
            self.closeSocket()
        }
    }
    
    func encodeAndStream(pixelBuffer: CVPixelBuffer, ntpTimestamp: Double) {
        self.sessionLock.lock()
        guard self.isStreamingActive, let session = self.compressionSession else {
            self.sessionLock.unlock()
            return
        }
        
        // Generate a strictly increasing, contiguous presentation time for the hardware encoder (90kHz ticks)
        let presentationTime = CMTime(value: self.frameCount, timescale: 90000)
        self.frameCount += 1
        
        // Pass the precise double NTP timestamp through sourceFrameRefCon
        let timestampUs = Int(ntpTimestamp * 1_000_000.0)
        let refCon = UnsafeMutableRawPointer(bitPattern: timestampUs)
        
        var flags: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: refCon,
            infoFlagsOut: &flags
        )
        self.sessionLock.unlock()
        
        if status != noErr {
            print("Video Streaming: VTCompressionSessionEncodeFrame failed with status: \(status)")
        }
    }
    
    // MARK: - Private Setup Methods
    
    private func setupCompressionSession(width: Int32, height: Int32, bitrate: Int, fps: Int) {
        var session: VTCompressionSession?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in
                guard status == noErr, let sampleBuffer = sampleBuffer else { return }
                
                let manager = Unmanaged<LiveVideoStreamingManager>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
                
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
            print("Video Streaming: Failed to create VTCompressionSession: \(status)")
            return
        }
        
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
    }
    
    private func setupUDPSocket(ip: String, port: Int) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            print("Video Streaming Socket: Failed to create socket")
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
            print("Video Streaming Socket: Invalid target IP: \(ip)")
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
        
        print("Video Streaming Socket: Bound UDP streaming socket targeting \(ip):\(port)")
    }
    
    private func closeSocket() {
        sessionLock.lock()
        let fd = self.socketFD
        self.socketFD = -1
        self.isSocketConfigured = false
        sessionLock.unlock()
        
        if fd >= 0 {
            close(fd)
        }
    }
    
    // MARK: - Frame Processing & Packetization (RFC 6184 H.264 RTP)
    
    private func processEncodedFrame(sampleBuffer: CMSampleBuffer, ntpTimestamp: Double) {
        self.sessionLock.lock()
        let socketReady = self.isSocketConfigured && self.socketFD >= 0
        self.sessionLock.unlock()
        
        guard socketReady else { return }
        
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
        
        guard status == noErr else { return }
        
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
