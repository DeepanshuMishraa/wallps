import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

/// Re-encodes a user video as HEVC Main 10 with temporal scalability
/// (`tscl`/`tsas` sub-layers). macOS's WallpaperAerialsExtension expects the
/// per-frame temporal-layer info to drive its lock/unlock ramp; without it,
/// custom aerial videos freeze or go black after the first unlock.
enum TemporalTranscoder {
    static let maxDurationSeconds: Double = 30
    private static let targetBitrate = 8_000_000

    /// Detects Apple-style HEVC temporal scalability (`tscl`/`tsas` sample
    /// groups) by scanning the video's `moov` box. Videos that already carry
    /// them play reliably on the lock screen and do not need re-encoding.
    static func hasTemporalScalability(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0

        var offset: UInt64 = 0
        while offset + 8 <= fileSize {
            try? handle.seek(toOffset: offset)
            guard let header = try? handle.read(upToCount: 8), header.count == 8 else { break }
            var boxSize = UInt64(be32(header, 0))
            let type = String(data: header[4...], encoding: .ascii) ?? ""
            if boxSize == 1 {
                guard let large = try? handle.read(upToCount: 8), large.count == 8 else { break }
                boxSize = be64(large, 0)
            } else if boxSize == 0 {
                boxSize = fileSize - offset
            }
            guard boxSize >= 8, offset + boxSize <= fileSize else { break }
            if type == "moov" {
                let limit = min(boxSize - 8, 16 * 1024 * 1024)
                if let moov = try? handle.read(upToCount: Int(limit)) {
                    return moov.range(of: Data("tscl".utf8)) != nil
                        && moov.range(of: Data("tsas".utf8)) != nil
                }
                return false
            }
            offset += boxSize
        }
        return false
    }

    private static func be32(_ data: Data, _ start: Int) -> UInt32 {
        (UInt32(data[start]) << 24)
            | (UInt32(data[start + 1]) << 16)
            | (UInt32(data[start + 2]) << 8)
            | UInt32(data[start + 3])
    }

    private static func be64(_ data: Data, _ start: Int) -> UInt64 {
        (UInt64(be32(data, start)) << 32) | UInt64(be32(data, start + 4))
    }

    static func transcode(input: URL, output: URL) throws {
        try? FileManager.default.removeItem(at: output)

        let asset = AVURLAsset(url: input)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw TemporalTranscodeError.noVideoTrack
        }
        guard track.naturalSize.width > 0, track.naturalSize.height > 0 else {
            throw TemporalTranscodeError.invalidDimensions
        }
        let width = Int32(Int(track.naturalSize.width.rounded()))
        let height = Int32(Int(track.naturalSize.height.rounded()))
        let fps = max(track.nominalFrameRate, 1)
        let clipDuration = min(asset.duration.seconds, maxDurationSeconds)

        // The lock-screen ramp only needs smooth motion up to 60 fps. Capping
        // there keeps high-frame-rate clips (e.g. 240 fps aerials) from
        // exploding into tens of thousands of frames to re-encode.
        let encodeFps = min(Double(fps), 60)
        let frameSkip = max(1, Int((Double(fps) / encodeFps).rounded()))
        // Encode at the source's own bit depth: 8-bit sources skip the costly
        // per-frame 10-bit conversion with no visible quality difference.
        let mediaFormat = (track.formatDescriptions as? [CMFormatDescription])?
            .first
            .map { CMFormatDescriptionGetMediaSubType($0) }
        let is10BitSource = mediaFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            || mediaFormat == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
        let readerPixelFormat: OSType = is10BitSource
            ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

        // Streams compressed frames into a .mov; writer is created lazily on the
        // first sample so we can pass the encoder's source format description.
        let writer = VideoPipeline(outputURL: output)
        var session: VTCompressionSession?
        let spec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
        ]
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { refcon, _, _, _, sampleBuffer in
                guard let sampleBuffer else { return }
                Unmanaged<VideoPipeline>.fromOpaque(refcon!)
                    .takeUnretainedValue()
                    .append(sampleBuffer)
            },
            refcon: Unmanaged.passUnretained(writer).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            throw TemporalTranscodeError.compressionSession(status)
        }

        func setProperty(_ key: CFString, _ value: CFTypeRef) {
            VTSessionSetProperty(session, key: key, value: value)
        }
        setProperty(kVTCompressionPropertyKey_RealTime, kCFBooleanFalse)
        setProperty(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main10_AutoLevel)
        setProperty(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanTrue)
        setProperty(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: encodeFps))
        setProperty(kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: Int(encodeFps * 5)))
        setProperty(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: targetBitrate))
        setProperty(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        setProperty(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
        setProperty(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        // Temporal scalability: two sub-layers so the ramp can drop the
        // enhancement layer without pausing playback.
        setProperty(kVTCompressionPropertyKey_AllowTemporalCompression, kCFBooleanTrue)
        setProperty(kVTCompressionPropertyKey_BaseLayerFrameRate, NSNumber(value: encodeFps / 2.0))
        VTCompressionSessionPrepareToEncodeFrames(session)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: readerPixelFormat
        ])
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)
        reader.startReading()
        guard reader.status == .reading else {
            throw TemporalTranscodeError.readerStart(reader.status)
        }

        var frameIndex = 0
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if CMTimeGetSeconds(time) > clipDuration { break }
            frameIndex += 1
            if frameIndex % frameSkip != 0 { continue }
            var duration = CMSampleBufferGetDuration(sampleBuffer)
            if !duration.isValid || duration.value == 0 {
                duration = CMTime(value: 1, timescale: Int32(encodeFps.rounded()))
            }
            VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: imageBuffer,
                presentationTimeStamp: time,
                duration: duration,
                frameProperties: nil,
                sourceFrameRefcon: nil,
                infoFlagsOut: nil
            )
        }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        try writer.finish()
    }
}

private final class VideoPipeline {
    private let lock = NSLock()
    private let outputURL: URL
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var started = false
    private var failure: Error?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard failure == nil, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if !started {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
            do {
                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
                input.expectsMediaDataInRealTime = false
                guard writer.canAdd(input) else {
                    failure = TemporalTranscodeError.writerSetup
                    return
                }
                writer.add(input)
                writer.startWriting()
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                guard writer.status != .failed else {
                    failure = writer.error ?? TemporalTranscodeError.writerSetup
                    return
                }
                self.writer = writer
                self.input = input
                started = true
            } catch {
                failure = error
                return
            }
        }

        guard let writer, let input else {
            failure = TemporalTranscodeError.writerSetup
            return
        }
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.0005)
        }
        if !input.append(sampleBuffer) {
            failure = writer.error ?? TemporalTranscodeError.writerFailed
        }
    }

    func finish() throws {
        lock.lock()
        let writer = self.writer
        let input = self.input
        lock.unlock()

        if let failure {
            throw failure
        }
        guard let writer, let input else {
            throw TemporalTranscodeError.nothingWritten
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else {
            throw writer.error ?? TemporalTranscodeError.writerFailed
        }
    }
}

enum TemporalTranscodeError: LocalizedError {
    case noVideoTrack
    case invalidDimensions
    case compressionSession(OSStatus)
    case readerStart(AVAssetReader.Status)
    case writerSetup
    case writerFailed
    case nothingWritten

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The file has no video track and cannot be used as a live wallpaper."
        case .invalidDimensions:
            return "The video has invalid dimensions and cannot be used."
        case .compressionSession(let status):
            return "The video encoder could not be created (OSStatus \(status))."
        case .readerStart(.failed):
            return "The video could not be read for transcode."
        case .readerStart:
            return "The video reader stopped before producing frames."
        case .writerSetup:
            return "The output movie could not be prepared."
        case .writerFailed:
            return "Writing the transcoded movie failed."
        case .nothingWritten:
            return "No frames were written — the video may be empty or unsupported."
        }
    }
}
