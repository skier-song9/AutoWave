@preconcurrency import AVFoundation
import Accelerate
import Foundation
import os

private final class AudioTapStateBox: @unchecked Sendable {
    private var state: AudioTapState?
    private var lock = os_unfair_lock_s()

    func replace(_ state: AudioTapState) {
        os_unfair_lock_lock(&lock)
        self.state = state
        os_unfair_lock_unlock(&lock)
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        state = nil
        os_unfair_lock_unlock(&lock)
    }

    func copyLatestSnapshot(
        ifNewerThan generation: UInt64,
        to destination: inout [Float]
    ) -> UInt64? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return state?.copyLatestSnapshot(
            ifNewerThan: generation,
            to: &destination
        )
    }
}

@MainActor
final class VisualizerTap {
    nonisolated static let bandCount = 16
    nonisolated static let fftSize = 1_024
    nonisolated static let tapBufferSize = AVAudioFrameCount(fftSize)

    private nonisolated let snapshotSource = AudioTapStateBox()
    @ObservationIgnored private var tapState: AudioTapState?
    @ObservationIgnored private var attachedEngine: AVAudioEngine?

    nonisolated static func bandBinRanges(sampleRate: Float, fftSize: Int) -> [Range<Int>] {
        let lowerFrequency: Float = 40
        let upperFrequency = min(8_000, sampleRate / 2)
        let halfSpectrumCount = fftSize / 2

        guard sampleRate > 0, fftSize > 1, upperFrequency > lowerFrequency else {
            return []
        }

        let frequencyRatio = pow(upperFrequency / lowerFrequency, 1 / Float(bandCount))
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(bandCount)

        var previousLowerBin = 1
        for index in 0..<bandCount {
            let lower = lowerFrequency * pow(frequencyRatio, Float(index))
            let upper = lowerFrequency * pow(frequencyRatio, Float(index + 1))
            let lowerBin = max(
                previousLowerBin,
                Int(floor(lower * Float(fftSize) / sampleRate))
            )
            let upperBin = min(
                halfSpectrumCount,
                max(lowerBin + 1, Int(ceil(upper * Float(fftSize) / sampleRate)))
            )

            ranges.append(lowerBin..<upperBin)
            previousLowerBin = upperBin
        }

        return ranges
    }

    init() { }

    func attach(to engine: AVAudioEngine) {
        detach()

        let sampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let state = AudioTapState(sampleRate: sampleRate)
        tapState = state
        snapshotSource.replace(state)
        attachedEngine = engine

        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: nil
        ) { @Sendable [state] buffer, _ in
            state.process(buffer: buffer)
        }
    }

    func detach() {
        attachedEngine?.mainMixerNode.removeTap(onBus: 0)
        attachedEngine = nil
        tapState = nil
        snapshotSource.clear()
    }

    nonisolated func copyLatestSnapshot(
        ifNewerThan generation: UInt64,
        to destination: inout [Float]
    ) -> UInt64? {
        snapshotSource.copyLatestSnapshot(
            ifNewerThan: generation,
            to: &destination
        )
    }
}

private final class AudioTapState: @unchecked Sendable {
    private let fftSetup: FFTSetup
    private let log2FFTSize: vDSP_Length
    private let sampleRate: Float
    private let bandRanges: [Range<Int>]
    private let window: UnsafeMutablePointer<Float>
    private let interleaved: UnsafeMutablePointer<DSPComplex>
    private let real: UnsafeMutablePointer<Float>
    private let imaginary: UnsafeMutablePointer<Float>
    private let latestBands: UnsafeMutablePointer<Float>
    private let latestSnapshot: UnsafeMutablePointer<Float>

    private var splitComplex: DSPSplitComplex
    private var processedFrames: AVAudioFramePosition = 0
    private var nextPublishFrame: AVAudioFramePosition
    private var snapshotGeneration: UInt64 = 0
    private var snapshotLock = os_unfair_lock_s()

    init(sampleRate: Float) {
        let validSampleRate = sampleRate > 0 ? sampleRate : 44_100
        let log2FFTSize = vDSP_Length(log2(Double(VisualizerTap.fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(
            log2FFTSize,
            FFTRadix(kFFTRadix2)
        ) else {
            fatalError("Unable to create visualizer FFT setup")
        }

        self.fftSetup = fftSetup
        self.log2FFTSize = log2FFTSize
        self.sampleRate = validSampleRate
        bandRanges = VisualizerTap.bandBinRanges(
            sampleRate: validSampleRate,
            fftSize: VisualizerTap.fftSize
        )
        window = UnsafeMutablePointer<Float>.allocate(capacity: VisualizerTap.fftSize)
        interleaved = UnsafeMutablePointer<DSPComplex>.allocate(
            capacity: VisualizerTap.fftSize / 2
        )
        real = UnsafeMutablePointer<Float>.allocate(capacity: VisualizerTap.fftSize / 2)
        imaginary = UnsafeMutablePointer<Float>.allocate(capacity: VisualizerTap.fftSize / 2)
        latestBands = UnsafeMutablePointer<Float>.allocate(capacity: VisualizerTap.bandCount)
        latestSnapshot = UnsafeMutablePointer<Float>.allocate(capacity: VisualizerTap.bandCount)
        splitComplex = DSPSplitComplex(realp: real, imagp: imaginary)
        nextPublishFrame = AVAudioFramePosition(validSampleRate / 30)

        window.initialize(repeating: 0, count: VisualizerTap.fftSize)
        interleaved.initialize(
            repeating: DSPComplex(real: 0, imag: 0),
            count: VisualizerTap.fftSize / 2
        )
        real.initialize(repeating: 0, count: VisualizerTap.fftSize / 2)
        imaginary.initialize(repeating: 0, count: VisualizerTap.fftSize / 2)
        latestBands.initialize(repeating: 0, count: VisualizerTap.bandCount)
        latestSnapshot.initialize(repeating: 0, count: VisualizerTap.bandCount)

        vDSP_hann_window(
            window,
            vDSP_Length(VisualizerTap.fftSize),
            Int32(vDSP_HANN_NORM)
        )
    }

    deinit {
        window.deinitialize(count: VisualizerTap.fftSize)
        window.deallocate()
        interleaved.deinitialize(count: VisualizerTap.fftSize / 2)
        interleaved.deallocate()
        real.deinitialize(count: VisualizerTap.fftSize / 2)
        real.deallocate()
        imaginary.deinitialize(count: VisualizerTap.fftSize / 2)
        imaginary.deallocate()
        latestBands.deinitialize(count: VisualizerTap.bandCount)
        latestBands.deallocate()
        latestSnapshot.deinitialize(count: VisualizerTap.bandCount)
        latestSnapshot.deallocate()
        vDSP_destroy_fftsetup(fftSetup)
    }

    func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = min(Int(buffer.frameLength), VisualizerTap.fftSize)
        let input = channelData[0]
        for sampleIndex in 0..<VisualizerTap.fftSize {
            let sample = sampleIndex < frameCount ? input[sampleIndex] : 0
            let weightedSample = sample * window[sampleIndex]
            let complexIndex = sampleIndex / 2
            if sampleIndex.isMultiple(of: 2) {
                interleaved[complexIndex].real = weightedSample
            } else {
                interleaved[complexIndex].imag = weightedSample
            }
        }

        vDSP_ctoz(
            interleaved,
            2,
            &splitComplex,
            1,
            vDSP_Length(VisualizerTap.fftSize / 2)
        )
        vDSP_fft_zrip(
            fftSetup,
            &splitComplex,
            1,
            log2FFTSize,
            FFTDirection(FFT_FORWARD)
        )

        for (index, range) in bandRanges.enumerated() {
            var totalMagnitude: Float = 0
            for bin in range {
                let realValue = real[bin]
                let imaginaryValue = imaginary[bin]
                totalMagnitude += sqrtf(
                    realValue * realValue + imaginaryValue * imaginaryValue
                )
            }

            let averageMagnitude = totalMagnitude / Float(max(range.count, 1))
            let linearMagnitude = averageMagnitude / Float(VisualizerTap.fftSize / 2)
            let normalizedMagnitude = min(
                max(log1pf(linearMagnitude * 9) / logf(10), 0),
                1
            )
            let previous = latestBands[index]
            let smoothing: Float = normalizedMagnitude > previous ? 0.3 : 0.15
            latestBands[index] = previous + (normalizedMagnitude - previous) * smoothing
        }

        processedFrames += AVAudioFramePosition(frameCount)
        guard processedFrames >= nextPublishFrame else { return }

        while nextPublishFrame <= processedFrames {
            nextPublishFrame += AVAudioFramePosition(sampleRate / 30)
        }

        os_unfair_lock_lock(&snapshotLock)
        for index in 0..<VisualizerTap.bandCount {
            latestSnapshot[index] = latestBands[index]
        }
        snapshotGeneration += 1
        os_unfair_lock_unlock(&snapshotLock)
    }

    func copyLatestSnapshot(ifNewerThan generation: UInt64, to destination: inout [Float]) -> UInt64? {
        guard destination.count == VisualizerTap.bandCount else { return nil }

        os_unfair_lock_lock(&snapshotLock)
        defer { os_unfair_lock_unlock(&snapshotLock) }

        guard snapshotGeneration > generation else { return nil }
        for index in 0..<VisualizerTap.bandCount {
            destination[index] = latestSnapshot[index]
        }
        return snapshotGeneration
    }
}
