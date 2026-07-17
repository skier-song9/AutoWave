@preconcurrency import AVFoundation
import Accelerate
import Foundation
import Observation

@MainActor
@Observable
final class VisualizerTap {
    nonisolated static let bandCount = 16
    nonisolated static let fftSize = 1_024
    nonisolated static let tapBufferSize = AVAudioFrameCount(fftSize)
    nonisolated static let snapshotSlotCount = 8

    private(set) var bands = [Float](repeating: 0, count: bandCount)

    @ObservationIgnored private var tapState: AudioTapState?
    @ObservationIgnored private var attachedEngine: AVAudioEngine?
    @ObservationIgnored private var publishWorkItems: PublishWorkItems?

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
        attachedEngine = engine

        var workItems: [DispatchWorkItem] = []
        workItems.reserveCapacity(Self.snapshotSlotCount)
        for slot in 0..<Self.snapshotSlotCount {
            workItems.append(DispatchWorkItem { @MainActor [weak self, state] in
                self?.publishLatestBands(from: state, slot: slot)
            })
        }
        let publishWorkItems = PublishWorkItems(workItems)
        self.publishWorkItems = publishWorkItems

        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: nil
        ) { [state, publishWorkItems] buffer, _ in
            guard let slot = state.process(buffer: buffer) else { return }
            DispatchQueue.main.async(execute: publishWorkItems[slot])
        }
    }

    func detach() {
        attachedEngine?.mainMixerNode.removeTap(onBus: 0)
        attachedEngine = nil
        tapState = nil
        publishWorkItems = nil
    }

    private func publishLatestBands(from state: AudioTapState, slot: Int) {
        guard tapState === state else { return }
        state.copySnapshot(slot: slot, to: &bands)
    }
}

private final class PublishWorkItems: @unchecked Sendable {
    private let items: [DispatchWorkItem]

    init(_ items: [DispatchWorkItem]) {
        self.items = items
    }

    subscript(index: Int) -> DispatchWorkItem {
        items[index]
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
    private let snapshots: UnsafeMutablePointer<Float>

    private var splitComplex: DSPSplitComplex
    private var processedFrames: AVAudioFramePosition = 0
    private var nextPublishFrame: AVAudioFramePosition
    private var nextSnapshotSlot = 0

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
        snapshots = UnsafeMutablePointer<Float>.allocate(
            capacity: VisualizerTap.bandCount * VisualizerTap.snapshotSlotCount
        )
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
        snapshots.initialize(
            repeating: 0,
            count: VisualizerTap.bandCount * VisualizerTap.snapshotSlotCount
        )

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
        snapshots.deinitialize(
            count: VisualizerTap.bandCount * VisualizerTap.snapshotSlotCount
        )
        snapshots.deallocate()
        vDSP_destroy_fftsetup(fftSetup)
    }

    func process(buffer: AVAudioPCMBuffer) -> Int? {
        guard let channelData = buffer.floatChannelData else { return nil }

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
        guard processedFrames >= nextPublishFrame else { return nil }

        while nextPublishFrame <= processedFrames {
            nextPublishFrame += AVAudioFramePosition(sampleRate / 30)
        }

        let slot = nextSnapshotSlot
        nextSnapshotSlot = (nextSnapshotSlot + 1) % VisualizerTap.snapshotSlotCount
        let snapshotStart = slot * VisualizerTap.bandCount
        for index in 0..<VisualizerTap.bandCount {
            snapshots[snapshotStart + index] = latestBands[index]
        }
        return slot
    }

    func copySnapshot(slot: Int, to destination: inout [Float]) {
        guard destination.count == VisualizerTap.bandCount else { return }
        guard slot >= 0, slot < VisualizerTap.snapshotSlotCount else { return }

        let snapshotStart = slot * VisualizerTap.bandCount
        for index in 0..<VisualizerTap.bandCount {
            destination[index] = snapshots[snapshotStart + index]
        }
    }
}
