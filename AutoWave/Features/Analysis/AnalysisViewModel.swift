import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AnalysisViewModel {
    enum State: Equatable, Sendable {
        case idle
        case analyzing(progress: Double)
        case generating(current: Int, total: Int)
        case done
        case failed(message: String)
    }

    private(set) var state: State = .idle

    static func shouldRegenerate(storedGeneratorVersions: [Int]) -> Bool {
        storedGeneratorVersions.contains { $0 < BeatmapGenerator.version }
    }

    static func needsRegeneration(for beatmaps: [BeatmapEntity]) -> Bool {
        let versions = beatmaps.compactMap { entity -> Int? in
            guard let beatmap = try? JSONDecoder().decode(
                Beatmap.self,
                from: entity.beatmapData
            ) else {
                return nil
            }
            return beatmap.generatorVersion
        }
        return shouldRegenerate(storedGeneratorVersions: versions)
    }

    func start(track: TrackEntity, context: ModelContext) async {
        state = .analyzing(progress: 0)

        do {
            let audioURL = track.audioURL
            let seed = try stableSeed(sourceFilename: track.sourceFilename, audioURL: audioURL)
            let analysis = try await BeatmapKit.analyze(fileAt: audioURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, case .analyzing = self.state else { return }
                    self.state = .analyzing(progress: min(max(progress, 0), 1))
                }
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var encodedBeatmaps: [(difficulty: Difficulty, data: Data)] = []
            encodedBeatmaps.reserveCapacity(Difficulty.allCases.count)

            for (index, difficulty) in Difficulty.allCases.enumerated() {
                let beatmap = BeatmapGenerator.generate(
                    from: analysis,
                    difficulty: difficulty,
                    seed: seed
                )
                encodedBeatmaps.append((difficulty, try encoder.encode(beatmap)))
                state = .generating(current: index + 1, total: Difficulty.allCases.count)
                await Task.yield()
            }

            for beatmap in track.beatmaps {
                context.delete(beatmap)
            }
            for item in encodedBeatmaps {
                context.insert(
                    BeatmapEntity(
                        difficulty: item.difficulty.rawValue,
                        beatmapData: item.data,
                        track: track
                    )
                )
            }

            try context.save()
            state = .done
        } catch {
            state = .failed(message: "분석에 실패했어요")
        }
    }

    private func stableSeed(sourceFilename: String, audioURL: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        guard let byteCount = (attributes[.size] as? NSNumber)?.uint64Value else {
            throw SeedError.fileSizeUnavailable
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(sourceFilename)-\(byteCount)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

private enum SeedError: Error {
    case fileSizeUnavailable
}
