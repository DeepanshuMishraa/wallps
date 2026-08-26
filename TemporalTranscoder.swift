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
        setProperty(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: Double(fps)))
        setProperty(kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: Int(fps * 5)))
        setProperty(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: targetBitrate))
        setProperty(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        setProperty(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
        setProperty(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        // Temporal scalability: two sub-layers so the ramp can drop the
        // enhancement layer without pausing playback.
        setProperty(kVTCompressionPropertyKey_AllowTemporalCompression, kCFBooleanTrue)
        setProperty(kVTCompressionPropertyKey_BaseLayerFrameRate, NSNumber(value: Double(fps) / 2.0))
        VTCompressionSessionPrepareToEncodeFrames(session)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        ])
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)
        reader.startReading()
        guard reader.status == .reading else {
            throw TemporalTranscodeError.readerStart(reader.status)
        }

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if CMTimeGetSeconds(time) > clipDuration { break }
            var duration = CMSampleBufferGetDuration(sampleBuffer)
            if !duration.isValid || duration.value == 0 {
                duration = CMTime(value: 1, timescale: Int32(fps.rounded()))
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
