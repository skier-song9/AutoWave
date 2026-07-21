import AVFoundation
import Foundation
import Observation
import os
import SpriteKit
import SwiftData

struct GameplaySummary: Equatable, Identifiable, Sendable {
    let id = UUID()
    let score: Int
    let maxCombo: Int
    let judgmentCounts: JudgmentCounts
    let failed: Bool
}

final class PlaybackClock: @unchecked Sendable {
    private weak var playerNode: AVAudioPlayerNode?
    private var offset: TimeInterval = 0
    private var finished = false
    private var completionGeneration: UInt64 = 0
    private var suppressCompletion = false
    private var lock = os_unfair_lock_s()

    init(playerNode: AVAudioPlayerNode) {
        self.playerNode = playerNode
    }

    var currentTime: TimeInterval {
        let offset = withLock { self.offset }
        guard
            let playerNode,
            let renderTime = playerNode.lastRenderTime,
            let playerTime = playerNode.playerTime(forNodeTime: renderTime),
            playerTime.sampleRate > 0
        else {
            return offset
        }

        return max(
            offset + Double(playerTime.sampleTime) / playerTime.sampleRate,
            0
        )
    }

    var isFinished: Bool {
        withLock { finished }
    }

    func setOffset(_ offset: TimeInterval) {
        withLock {
            self.offset = max(offset, 0)
        }
    }

    func setFinished(_ finished: Bool) {
        withLock {
            self.finished = finished
        }
    }

    func beginPlayback() -> UInt64 {
        withLock {
            completionGeneration &+= 1
            suppressCompletion = false
            finished = false
            return completionGeneration
        }
    }

    func beginManualStop() {
        withLock {
            completionGeneration &+= 1
            suppressCompletion = true
        }
    }

    func completePlayback(for generation: UInt64) {
        withLock {
            guard !suppressCompletion, generation == completionGeneration else { return }
            finished = true
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }
}

final class NoteSpeedMultiplierState: @unchecked Sendable {
    static let allowedValues: [CGFloat] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    private var storedValue: CGFloat
    private var lock = os_unfair_lock_s()

    init(_ value: CGFloat = 1) {
        storedValue = value
    }

    var value: CGFloat {
        withLock { storedValue }
    }

    func set(_ value: CGFloat) {
        withLock {
            storedValue = value
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }
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
    private(set) var isPaused = false
    private(set) var countdown: Int?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var audioFile: AVAudioFile?
    @ObservationIgnored private var playerNode: AVAudioPlayerNode?
    @ObservationIgnored private var visualizerTap: VisualizerTap?
    @ObservationIgnored private var gameplayScene: GameScene?
    @ObservationIgnored private var playbackClock: PlaybackClock?
    @ObservationIgnored private let noteSpeedState: NoteSpeedMultiplierState
    @ObservationIgnored private var hasCompleted = false
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var perfectHaptic: UIImpactFeedbackGenerator?
    @ObservationIgnored private var lightHaptic: UIImpactFeedbackGenerator?
    @ObservationIgnored private var dragBreakHaptic: UINotificationFeedbackGenerator?

    init(
        track: TrackEntity,
        difficulty: Difficulty,
        noteSpeedState: NoteSpeedMultiplierState = NoteSpeedMultiplierState()
    ) {
        self.track = track
        self.difficulty = difficulty
        self.noteSpeedState = noteSpeedState
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
            prepareHaptics()
            let profile = ProfileEntity.current(in: context)
            let speedMultiplier = Self.validNoteSpeedMultiplier(profile.noteSpeedMultiplier)
            guard let beatmapEntity = track.beatmaps.first(where: {
                $0.difficulty == difficulty.rawValue
            }) else {
                throw GameplayError.beatmapMissing
            }

            var decodedBeatmap = try JSONDecoder().decode(Beatmap.self, from: beatmapEntity.beatmapData)
            decodedBeatmap.notes = GameplayBeatmapSanitizer.removeTapConflicts(from: decodedBeatmap.notes)
            let judgmentEngine = JudgmentEngine(notes: decodedBeatmap.notes)
            let newAudioFile = try AVAudioFile(forReading: track.audioURL)
            let newAudioEngine = AVAudioEngine()
            let newPlayerNode = AVAudioPlayerNode()

            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            newAudioEngine.attach(newPlayerNode)
            newAudioEngine.connect(
                newPlayerNode,
                to: newAudioEngine.mainMixerNode,
                format: newAudioFile.processingFormat
            )
            let clock = PlaybackClock(playerNode: newPlayerNode)
            let generation = clock.beginPlayback()
            newPlayerNode.scheduleFile(
                newAudioFile,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { @Sendable [clock] _ in
                clock.completePlayback(for: generation)
            }
            try newAudioEngine.start()
            let newVisualizerTap = VisualizerTap()
            newVisualizerTap.attach(to: newAudioEngine)
            newPlayerNode.play()

            beatmap = decodedBeatmap
            engine = judgmentEngine
            audioEngine = newAudioEngine
            audioFile = newAudioFile
            playerNode = newPlayerNode
            visualizerTap = newVisualizerTap
            playbackClock = clock
            hasCompleted = false
            isPaused = false
            countdown = nil
            saveErrorMessage = nil
            noteSpeedState.set(CGFloat(speedMultiplier))
            let speedState = noteSpeedState
            gameplayScene = GameScene(
                beatmap: decodedBeatmap,
                difficulty: difficulty,
                judgmentEngine: judgmentEngine,
                visualizerTap: newVisualizerTap,
                noteSpeedState: speedState,
                playbackTime: {
                    clock.currentTime
                },
                playbackFinished: {
                    clock.isFinished
                },
                audioDuration: newAudioFile.processingFormat.sampleRate > 0
                    ? Double(newAudioFile.length) / newAudioFile.processingFormat.sampleRate
                    : 0,
                onComplete: { [weak self] failed in
                    Task { @MainActor [weak self] in
                        self?.complete(
                            context: context,
                            failed: failed,
                            onComplete: onComplete
                        )
                    }
                },
                onHaptic: { [weak self] event in
                    Task { @MainActor [weak self] in
                        self?.emitHaptic(event)
                    }
                }
            )
            state = .ready
        } catch {
            state = .failed(message: "게임을 시작하지 못했어요")
        }
    }

    func currentPlaybackTime() -> TimeInterval {
        playbackClock?.currentTime ?? 0
    }

    func pause() {
        guard state == .ready, !isPaused else { return }

        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        let offset = playbackClock?.currentTime ?? 0
        playbackClock?.setOffset(offset)
        isPaused = true
        gameplayScene?.isPaused = true
        playbackClock?.beginManualStop()
        playerNode?.stop()
        audioEngine?.pause()
    }

    func resume() {
        guard state == .ready, isPaused, countdownTask == nil else { return }

        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for value in stride(from: 3, through: 1, by: -1) {
                countdown = value
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }

            countdown = nil
            resumePlayback()
            countdownTask = nil
        }
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        isPaused = false
        gameplayScene?.isPaused = false
        visualizerTap?.detach()
        playbackClock?.beginManualStop()
        playerNode?.stop()
        audioEngine?.stop()
        audioFile = nil
        visualizerTap = nil
        playbackClock = nil
    }

    private func resumePlayback() {
        guard
            let audioFile,
            let audioEngine,
            let playerNode,
            let playbackClock
        else {
            state = .failed(message: "재생을 다시 시작하지 못했어요")
            return
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else {
            state = .failed(message: "재생을 다시 시작하지 못했어요")
            return
        }

        let playbackOffset = playbackClock.currentTime
        playbackClock.setOffset(playbackOffset)
        let startingFrame = min(
            max(AVAudioFramePosition((playbackOffset * sampleRate).rounded()), 0),
            audioFile.length
        )
        let remainingFrames = audioFile.length - startingFrame
        guard remainingFrames > 0 else {
            playbackClock.setFinished(true)
            isPaused = false
            gameplayScene?.isPaused = false
            return
        }

        let generation = playbackClock.beginPlayback()
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startingFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { @Sendable [playbackClock] _ in
            playbackClock.completePlayback(for: generation)
        }

        do {
            try audioEngine.start()
            playerNode.play()
            isPaused = false
            gameplayScene?.isPaused = false
        } catch {
            state = .failed(message: "재생을 다시 시작하지 못했어요")
        }
    }

    private func complete(
        context: ModelContext,
        failed: Bool,
        onComplete: @escaping (GameplaySummary) -> Void
    ) {
        guard !hasCompleted, let engine else { return }

        hasCompleted = true
        stop()

        let summary = GameplaySummary(
            score: engine.score,
            maxCombo: engine.maxCombo,
            judgmentCounts: engine.judgmentCounts,
            failed: failed || engine.isGameOver
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

    private func prepareHaptics() {
        perfectHaptic = UIImpactFeedbackGenerator(style: .rigid)
        lightHaptic = UIImpactFeedbackGenerator(style: .light)
        dragBreakHaptic = UINotificationFeedbackGenerator()
        perfectHaptic?.prepare()
        lightHaptic?.prepare()
        dragBreakHaptic?.prepare()
    }

    private func emitHaptic(_ event: GameplayHaptic) {
        switch event {
        case .perfect:
            perfectHaptic?.impactOccurred(intensity: 0.7)
            perfectHaptic?.prepare()
        case .light:
            lightHaptic?.impactOccurred()
            lightHaptic?.prepare()
        case .warning:
            dragBreakHaptic?.notificationOccurred(.warning)
            dragBreakHaptic?.prepare()
        }
    }

    private static func validNoteSpeedMultiplier(_ value: Double) -> Double {
        NoteSpeedMultiplierState.allowedValues.first {
            abs(Double($0) - value) < 0.000_001
        }.map { Double($0) } ?? 1.0
    }
}

private enum GameplayError: Error {
    case beatmapMissing
}
