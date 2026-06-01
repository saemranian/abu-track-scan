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
    
    // POSIX BSD Socket properties for ultra-low latency streaming
    private var socketFD: Int32 = -1
    private var targetAddr = sockaddr_in()
    private var isSocketConfigured = false
    
    private var rtpSequenceNumber: UInt16 = 0
    private let ssrc: UInt32 = 0x12345678
    
    private var currentIP: String = ""
    private var currentPort: Int = 0
    private var isStreamingActive = false
    
    override init() {
        super.init()
    }
    
    func startStreaming(ip: String, port: Int, width: Int32 = 1920, height: Int32 = 1080, bitrate: Int = 10_000_000, fps: Int = 30) {
        encodingQueue.async {
            guard !self.isStreamingActive else { return }
            
            print("Video Streaming: Initializing stream to \(ip):\(port) with resolution \(width)x\(height) @ \(bitrate / 1_000_000) Mbps")
            
            self.currentIP = ip
            self.currentPort = port
            
            // 1. Setup UDP Socket
            self.setupUDPSocket(ip: ip, port: port)
            
            // 2. Setup VideoToolbox Compression Session
            self.setupCompressionSession(width: width, height: height, bitrate: bitrate, fps: fps)
            
            self.isStreamingActive = true
            print("Video Streaming: Stream successfully active.")
        }
    }
    
    func stopStreaming() {
        encodingQueue.async {
            guard self.isStreamingActive else { return }
            print("Video Streaming: Terminating streaming sessions.")
            self.isStreamingActive = false
            
            // Teardown VideoToolbox Session
            if let session = self.compressionSession {
                VTCompressionSessionInvalidate(session)
                self.compressionSession = nil
            }
            
            // Close Socket
            self.closeSocket()
        }
    }
    
    func encodeAndStream(pixelBuffer: CVPixelBuffer, ntpTimestamp: Double) {
        encodingQueue.async {
            guard self.isStreamingActive, let session = self.compressionSession else { return }
            
            // Use presentation timestamp or arbitrary incrementing ticks
            let presentationTime = CMTime(value: Int64(ntpTimestamp * 1000.0), timescale: 1000)
            
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
            
            if status != noErr {
                print("Video Streaming: VTCompressionSessionEncodeFrame failed with status: \(status)")
            }
        }
    }
    
    // MARK: - Private Setup Methods
    
    private func setupCompressionSession(width: Int32, height: Int32, bitrate: Int, fps: Int) {
        if let oldSession = self.compressionSession {
            VTCompressionSessionInvalidate(oldSession)
            self.compressionSession = nil
        }
        
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
                
                manager.processEncodedFrame(sampleBuffer: sampleBuffer, ntpTimestamp: originalNtpTime)
            },
            refcon: selfPtr,
            compressionSessionOut: &self.compressionSession
        )
        
        guard status == noErr, let session = self.compressionSession else {
            print("Video Streaming: Failed to create VTCompressionSession: \(status)")
            return
        }
        
        // Configure Hardware encoding options for ultra low latency virtual production
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: fps as CFNumber) // I-frame every 1s
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse) // No B-Frames
        
        // Start session
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    private func setupUDPSocket(ip: String, port: Int) {
        closeSocket()
        
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            print("Video Streaming Socket: Failed to create socket")
            return
        }
        
        // Enable SO_BROADCAST in case we stream to subnet
        var broadcastEnable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))
        
        self.socketFD = fd
        
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
            self.socketFD = -1
            return
        }
        addr.sin_addr.s_addr = resolved
        
        self.targetAddr = addr
        self.isSocketConfigured = true
        print("Video Streaming Socket: Bound UDP streaming socket targeting \(ip):\(port)")
    }
    
    private func closeSocket() {
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        isSocketConfigured = false
    }
    
    // MARK: - Frame Processing & Packetization (RFC 6184 H.264 RTP)
    
    private func processEncodedFrame(sampleBuffer: CMSampleBuffer, ntpTimestamp: Double) {
        guard isSocketConfigured, socketFD >= 0 else { return }
        
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
        var totalLength = 0
        var lengthAtOffset = 0
        var dataPointer: UnsafeMutablePointer<CChar>?
        
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        
        if status == noErr, let basePointer = dataPointer {
            var offset = 0
            while offset < totalLength {
                // AVCC format: NALU is prefixed by 4-byte big-endian length field
                var naluLength: UInt32 = 0
                memcpy(&naluLength, basePointer + offset, 4)
                naluLength = CFSwapInt32BigToHost(naluLength)
                
                offset += 4
                
                if offset + Int(naluLength) <= totalLength {
                    let naluData = Data(bytes: basePointer + offset, count: Int(naluLength))
                    let isLastNalu = (offset + Int(naluLength) >= totalLength)
                    sendNALUnit(naluData, ntpTimestamp: ntpTimestamp, isLast: isLastNalu)
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
            
            sendPacket(packet)
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
                
                sendPacket(packet)
                
                bytesSent += chunkSize
            }
        }
    }
    
    private func sendPacket(_ data: Data) {
        guard socketFD >= 0 else { return }
        
        let count = data.count
        _ = withUnsafePointer(to: &targetAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                data.withUnsafeBytes { dataBytes in
                    sendto(socketFD, dataBytes.baseAddress, count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
    
    deinit {
        closeSocket()
    }
}
