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

    nonisolated static func shouldRegenerate(
        storedLaneCount: Int?,
        chosenLaneCount: Int,
        storedGeneratorVersion: Int?
    ) -> Bool {
        guard let storedLaneCount, let storedGeneratorVersion else { return true }
        return storedLaneCount != chosenLaneCount
            || storedGeneratorVersion < BeatmapGenerator.version
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
            let analysis = try await loadOrAnalyze(track: track)
            let seed = try stableSeed(sourceFilename: track.sourceFilename, audioURL: track.audioURL)
            var encodedBeatmaps: [(difficulty: Difficulty, data: Data)] = []
            encodedBeatmaps.reserveCapacity(Difficulty.allCases.count)

            for (index, difficulty) in Difficulty.allCases.enumerated() {
                let beatmap = BeatmapGenerator.generate(
                    from: analysis,
                    difficulty: difficulty,
                    seed: seed
                )
                encodedBeatmaps.append((difficulty, try encode(beatmap)))
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

    func regenerate(
        track: TrackEntity,
        difficulty: Difficulty,
        laneCountOverride: Int,
        context: ModelContext
    ) async {
        state = .analyzing(progress: 0)

        do {
            let analysis = try await loadOrAnalyze(track: track)
            let seed = try stableSeed(sourceFilename: track.sourceFilename, audioURL: track.audioURL)
            let beatmap = BeatmapGenerator.generate(
                from: analysis,
                difficulty: difficulty,
                seed: seed,
                laneCountOverride: laneCountOverride
            )
            state = .generating(current: 1, total: 1)

            for entity in track.beatmaps where entity.difficulty == difficulty.rawValue {
                context.delete(entity)
            }
            context.insert(
                BeatmapEntity(
                    difficulty: difficulty.rawValue,
                    beatmapData: try encode(beatmap),
                    track: track
                )
            )
            try context.save()
            state = .done
        } catch {
            state = .failed(message: "비트맵을 준비하지 못했어요")
        }
    }

    static func resetConversion(for track: TrackEntity, in context: ModelContext) throws {
        for beatmap in Array(track.beatmaps) {
            context.delete(beatmap)
        }
        track.beatmaps = []
        track.analysisData = nil

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func loadOrAnalyze(track: TrackEntity) async throws -> AnalysisResult {
        if let data = track.analysisData,
           let analysis = try? JSONDecoder().decode(AnalysisResult.self, from: data) {
            state = .analyzing(progress: 1)
            return analysis
        }

        let analysis = try await BeatmapKit.analyze(fileAt: track.audioURL) { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, case .analyzing = self.state else { return }
                self.state = .analyzing(progress: min(max(progress, 0), 1))
            }
        }
        track.analysisData = try encode(analysis)
        return analysis
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
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
