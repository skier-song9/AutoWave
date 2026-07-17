@preconcurrency import AVFoundation
import Foundation

struct DecodedAudio: Sendable {
    var samples: [Float]
    var sampleRate: Double
    var duration: TimeInterval
}

enum AudioDecoderError: Error {
    case invalidInputFormat
    case conversionFailed
}

private final class ConverterInputState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var providedInput = false
    var reachedEnd = false
    var readError: Error?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

enum AudioDecoder {
    static let outputSampleRate = 22_050.0

    static func decode(
        fileAt url: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> DecodedAudio {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        guard inputFormat.sampleRate > 0, file.length > 0 else {
            return DecodedAudio(samples: [], sampleRate: outputSampleRate, duration: 0)
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioDecoderError.invalidInputFormat
        }

        let inputCapacity: AVAudioFrameCount = 4_096
        let outputCapacity = AVAudioFrameCount(
            ceil(Double(inputCapacity) * outputSampleRate / inputFormat.sampleRate)
        ) + 1_024
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: inputCapacity
        )!
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        )!

        var samples: [Float] = []
        samples.reserveCapacity(
            Int(ceil(Double(file.length) * outputSampleRate / inputFormat.sampleRate))
        )

        while true {
            outputBuffer.frameLength = 0
            var conversionError: NSError?
            let inputState = ConverterInputState(buffer: inputBuffer)

            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, statusPointer in
                if inputState.providedInput {
                    statusPointer.pointee = .noDataNow
                    return nil
                }

                guard file.framePosition < file.length else {
                    inputState.reachedEnd = true
                    statusPointer.pointee = .endOfStream
                    return nil
                }

                let remainingFrames = file.length - file.framePosition
                let frameCount = AVAudioFrameCount(
                    min(Int64(inputCapacity), remainingFrames)
                )
                inputState.buffer.frameLength = 0
                do {
                    try file.read(into: inputState.buffer, frameCount: frameCount)
                    inputState.providedInput = inputState.buffer.frameLength > 0
                    if inputState.providedInput {
                        statusPointer.pointee = .haveData
                        return inputState.buffer
                    }
                } catch {
                    inputState.readError = error
                }

                inputState.reachedEnd = true
                statusPointer.pointee = .endOfStream
                return nil
            }

            if let readError = inputState.readError {
                throw readError
            }
            if let conversionError {
                throw conversionError
            }
            if status == .error {
                throw AudioDecoderError.conversionFailed
            }

            if outputBuffer.frameLength > 0, let channelData = outputBuffer.floatChannelData {
                let convertedSamples = UnsafeBufferPointer(
                    start: channelData[0],
                    count: Int(outputBuffer.frameLength)
                )
                samples.append(contentsOf: convertedSamples)
            } else if !inputState.providedInput && !inputState.reachedEnd {
                throw AudioDecoderError.conversionFailed
            }

            if inputState.reachedEnd {
                break
            }
        }

        progress?(1)
        let duration = TimeInterval(samples.count) / outputSampleRate
        return DecodedAudio(
            samples: samples,
            sampleRate: outputSampleRate,
            duration: duration
        )
    }
}
