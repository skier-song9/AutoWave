import Accelerate
import Foundation

struct SpectralFrame: Sendable {
    var flux: Float
    var bass: Float
    var mid: Float
    var treble: Float
    var centroid: Float
    var rms: Float
}

struct SpectralAnalysis: Sendable {
    var frames: [SpectralFrame]
}

enum SpectralAnalyzer {
    static let sampleRate = 22_050.0
    static let fftSize = 1_024
    static let hopSize = 512

    static func analyze(
        _ samples: [Float],
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> SpectralAnalysis {
        guard !samples.isEmpty else {
            return SpectralAnalysis(frames: [])
        }

        let frameCount = (samples.count + hopSize - 1) / hopSize
        let halfSpectrumCount = fftSize / 2
        let log2FFTSize = vDSP_Length(log2(Double(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2FFTSize, FFTRadix(kFFTRadix2)) else {
            return SpectralAnalysis(frames: [])
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var window = [Float](repeating: 0, count: fftSize)
        window.withUnsafeMutableBufferPointer { windowPointer in
            vDSP_hann_window(
                windowPointer.baseAddress!,
                vDSP_Length(fftSize),
                Int32(vDSP_HANN_NORM)
            )
        }

        var interleaved = [DSPComplex](
            repeating: DSPComplex(real: 0, imag: 0),
            count: halfSpectrumCount
        )
        var real = [Float](repeating: 0, count: halfSpectrumCount)
        var imaginary = [Float](repeating: 0, count: halfSpectrumCount)
        var magnitudes = [Float](repeating: 0, count: halfSpectrumCount)
        var previousLogMagnitude = [Float](repeating: 0, count: halfSpectrumCount)
        var currentLogMagnitude = [Float](repeating: 0, count: halfSpectrumCount)
        var frames: [SpectralFrame] = []
        frames.reserveCapacity(frameCount)

        let bassStart = 1
        let bassEnd = min(
            halfSpectrumCount,
            max(bassStart + 1, Int(ceil(250 * Double(fftSize) / sampleRate)))
        )
        let midEnd = min(
            halfSpectrumCount,
            max(bassEnd + 1, Int(ceil(2_000 * Double(fftSize) / sampleRate)))
        )
        let trebleCount = max(1, halfSpectrumCount - midEnd)
        let bassCount = max(1, bassEnd - bassStart)
        let midCount = max(1, midEnd - bassEnd)
        let powerScale = 1 / Float(fftSize * fftSize)

        window.withUnsafeBufferPointer { windowPointer in
            interleaved.withUnsafeMutableBufferPointer { interleavedPointer in
                real.withUnsafeMutableBufferPointer { realPointer in
                    imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                        magnitudes.withUnsafeMutableBufferPointer { magnitudePointer in
                            previousLogMagnitude.withUnsafeMutableBufferPointer { previousPointer in
                                currentLogMagnitude.withUnsafeMutableBufferPointer { currentPointer in
                                    var splitComplex = DSPSplitComplex(
                                        realp: realPointer.baseAddress!,
                                        imagp: imaginaryPointer.baseAddress!
                                    )

                                    for frameIndex in 0..<frameCount {
                                        let frameStart = frameIndex * hopSize - hopSize
                                        var rmsSum: Float = 0

                                        for sampleIndex in 0..<fftSize {
                                            let sourceIndex = frameStart + sampleIndex
                                            let sample = sourceIndex >= 0 && sourceIndex < samples.count
                                                ? samples[sourceIndex]
                                                : 0
                                            rmsSum += sample * sample
                                            let weightedSample = sample * windowPointer[sampleIndex]
                                            let complexIndex = sampleIndex / 2
                                            if sampleIndex.isMultiple(of: 2) {
                                                interleavedPointer[complexIndex].real = weightedSample
                                            } else {
                                                interleavedPointer[complexIndex].imag = weightedSample
                                            }
                                        }

                                        vDSP_ctoz(
                                            interleavedPointer.baseAddress!,
                                            2,
                                            &splitComplex,
                                            1,
                                            vDSP_Length(halfSpectrumCount)
                                        )
                                        vDSP_fft_zrip(
                                            fftSetup,
                                            &splitComplex,
                                            1,
                                            log2FFTSize,
                                            FFTDirection(FFT_FORWARD)
                                        )

                                        magnitudePointer[0] = 0
                                        currentPointer[0] = 0
                                        var flux: Float = 0
                                        var totalMagnitude: Float = 0
                                        var weightedMagnitude: Float = 0
                                        var bassEnergy: Float = 0
                                        var midEnergy: Float = 0
                                        var trebleEnergy: Float = 0

                                        for bin in 1..<halfSpectrumCount {
                                            let realValue = realPointer[bin]
                                            let imaginaryValue = imaginaryPointer[bin]
                                            let magnitude = sqrtf(
                                                realValue * realValue + imaginaryValue * imaginaryValue
                                            )
                                            magnitudePointer[bin] = magnitude
                                            let logMagnitude = log1pf(magnitude)
                                            currentPointer[bin] = logMagnitude
                                            let delta = logMagnitude - previousPointer[bin]
                                            if delta > 0 {
                                                flux += delta
                                            }

                                            let frequency = Float(bin) * Float(sampleRate) / Float(fftSize)
                                            totalMagnitude += magnitude
                                            weightedMagnitude += magnitude * frequency
                                            let energy = (
                                                realValue * realValue + imaginaryValue * imaginaryValue
                                            ) * powerScale
                                            if bin < bassEnd {
                                                bassEnergy += energy
                                            } else if bin < midEnd {
                                                midEnergy += energy
                                            } else {
                                                trebleEnergy += energy
                                            }
                                        }

                                        for bin in 0..<halfSpectrumCount {
                                            previousPointer[bin] = currentPointer[bin]
                                        }

                                        frames.append(
                                            SpectralFrame(
                                                flux: flux,
                                                bass: bassEnergy / Float(bassCount),
                                                mid: midEnergy / Float(midCount),
                                                treble: trebleEnergy / Float(trebleCount),
                                                centroid: totalMagnitude > 0
                                                    ? weightedMagnitude / totalMagnitude
                                                    : 0,
                                                rms: sqrtf(rmsSum / Float(fftSize))
                                            )
                                        )
                                        progress?(Double(frameIndex + 1) / Double(frameCount))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return SpectralAnalysis(frames: frames)
    }
}
