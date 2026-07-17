import AVFoundation
import Foundation
import Observation
import SpriteKit
import SwiftData

struct GameplaySummary: Equatable, Identifiable, Sendable {
    let id = UUID()
    let score: Int
    let maxCombo: Int
    let judgmentCounts: JudgmentCounts
}

@MainActor
@Observable
final class GameplayViewModel {
    enum State: Equatable, Sendable {
        case idle
        case ready
        case failed(message: String)
        case completed
    }

    let track: TrackEntity
    let difficulty: Difficulty

    private(set) var state: State = .idle
    private(set) var beatmap: Beatmap?
    private(set) var engine: JudgmentEngine?
    private(set) var saveErrorMessage: String?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var playerNode: AVAudioPlayerNode?
    @ObservationIgnored private var gameplayScene: GameScene?
    @ObservationIgnored private var audioFinished = false
    @ObservationIgnored private var hasCompleted = false

    init(track: TrackEntity, difficulty: Difficulty) {
        self.track = track
        self.difficulty = difficulty
    }

    var scene: GameScene? {
        gameplayScene
    }

    func start(
        context: ModelContext,
        onComplete: @escaping (GameplaySummary) -> Void
    ) {
        guard state == .idle else { return }

        do {
            guard let beatmapEntity = track.beatmaps.first(where: {
                $0.difficulty == difficulty.rawValue
            }) else {
                throw GameplayError.beatmapMissing
            }

            let decodedBeatmap = try JSONDecoder().decode(Beatmap.self, from: beatmapEntity.beatmapData)
            let judgmentEngine = JudgmentEngine(notes: decodedBeatmap.notes)
            let audioFile = try AVAudioFile(forReading: track.audioURL)
            let newAudioEngine = AVAudioEngine()
            let newPlayerNode = AVAudioPlayerNode()

            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            newAudioEngine.attach(newPlayerNode)
            newAudioEngine.connect(
                newPlayerNode,
                to: newAudioEngine.mainMixerNode,
                format: audioFile.processingFormat
            )
            newPlayerNode.scheduleFile(audioFile, at: nil) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.audioFinished = true
                }
            }
            try newAudioEngine.start()
            newPlayerNode.play()

            beatmap = decodedBeatmap
            engine = judgmentEngine
            audioEngine = newAudioEngine
            playerNode = newPlayerNode
            audioFinished = false
            hasCompleted = false
            saveErrorMessage = nil
            gameplayScene = GameScene(
                beatmap: decodedBeatmap,
                difficulty: difficulty,
                judgmentEngine: judgmentEngine,
                playbackTime: { [weak self] in
                    self?.currentPlaybackTime() ?? 0
                },
                playbackFinished: { [weak self] in
                    self?.audioFinished ?? false
                },
                onComplete: { [weak self] in
                    self?.complete(context: context, onComplete: onComplete)
                }
            )
            state = .ready
        } catch {
            state = .failed(message: "게임을 시작하지 못했어요")
        }
    }

    func currentPlaybackTime() -> TimeInterval {
        guard
            let playerNode,
            let renderTime = playerNode.lastRenderTime,
            let playerTime = playerNode.playerTime(forNodeTime: renderTime),
            playerTime.sampleRate > 0
        else {
            return 0
        }

        return max(Double(playerTime.sampleTime) / playerTime.sampleRate, 0)
    }

    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
    }

    private func complete(
        context: ModelContext,
        onComplete: @escaping (GameplaySummary) -> Void
    ) {
        guard !hasCompleted, let engine else { return }

        hasCompleted = true
        stop()

        let summary = GameplaySummary(
            score: engine.score,
            maxCombo: engine.maxCombo,
            judgmentCounts: engine.judgmentCounts
        )
        let record = ScoreRecord(
            track: track,
            difficulty: difficulty.rawValue,
            score: summary.score,
            maxCombo: summary.maxCombo,
            playedAt: Date()
        )
        context.insert(record)

        do {
            try context.save()
        } catch {
            saveErrorMessage = "결과를 저장하지 못했어요"
        }

        state = .completed
        onComplete(summary)
    }
}

private enum GameplayError: Error {
    case beatmapMissing
}
