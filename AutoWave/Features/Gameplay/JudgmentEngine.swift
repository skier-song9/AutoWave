import Foundation

enum Judgment: Equatable, Sendable {
    case perfect
    case great
    case good
    case bad
    case miss
}

enum DragTickResult: Equatable, Sendable {
    case scored(points: Int, combo: Int)
    case broken
    case finished
    case inactive
}

struct JudgmentResult: Equatable, Sendable {
    var judgment: Judgment
    var pointsAwarded: Int
    var combo: Int
    var score: Int
}

struct JudgmentCounts: Equatable, Sendable {
    var perfect = 0
    var great = 0
    var good = 0
    var bad = 0
    var miss = 0
}

// Mutations are serialized by SpriteKit scene callbacks; the view model reads final counters after completion.
final class JudgmentEngine: @unchecked Sendable {
    private struct PendingNote {
        let note: Note
        var consumed = false
    }

    private enum DragLifecycle {
        case pending
        case active
        case broken
        case finished
        case inactive
    }

    private struct DragState {
        let note: Note
        var lifecycle: DragLifecycle = .pending
    }

    private enum Window {
        static let perfect: TimeInterval = 0.045
        static let great: TimeInterval = 0.080
        static let good: TimeInterval = 0.115
        static let bad: TimeInterval = 0.150
        static let comparisonEpsilon: TimeInterval = 0.000_000_001
        static let dragLaneTolerance = 0.6
    }

    private var pendingNotes: [PendingNote]
    private var dragStates: [DragState]

    private(set) var score = 0
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var judgmentCounts = JudgmentCounts()
    private(set) var life = 100
    private(set) var isGameOver = false
    private var scoreThresholdsPassed = 0

    init(notes: [Note]) {
        pendingNotes = notes
            .filter { $0.kind == .tap }
            .sorted { $0.time < $1.time }
            .map { PendingNote(note: $0) }
        dragStates = notes
            .filter { $0.kind == .drag }
            .sorted { $0.time < $1.time }
            .map { DragState(note: $0) }
    }

    @discardableResult
    func tap(lane: Int, at time: TimeInterval) -> JudgmentResult? {
        guard let index = nearestUnconsumedNoteIndex(lane: lane, at: time) else {
            return nil
        }

        pendingNotes[index].consumed = true
        let offset = abs(pendingNotes[index].note.time - time)
        return award(judgment: judgment(for: offset))
    }

    @discardableResult
    func beginDrag(
        noteID: UUID,
        touchLane: Double,
        at time: TimeInterval
    ) -> JudgmentResult? {
        guard let index = dragStateIndex(for: noteID), dragStates[index].lifecycle == .pending else {
            return nil
        }

        let note = dragStates[index].note
        let timeOffset = abs(note.time - time)
        guard timeOffset <= Window.bad + Window.comparisonEpsilon else {
            return nil
        }

        let spineLane = lane(at: 0, for: note)
        guard abs(touchLane - spineLane) <= Window.dragLaneTolerance + Window.comparisonEpsilon else {
            return nil
        }

        let result = award(judgment: judgment(for: timeOffset))
        dragStates[index].lifecycle = .active
        return result
    }

    func dragTick(
        noteID: UUID,
        touchLane: Double?,
        at time: TimeInterval
    ) -> DragTickResult {
        guard let index = dragStateIndex(for: noteID), dragStates[index].lifecycle == .active else {
            return .inactive
        }

        let note = dragStates[index].note
        guard time < note.time + note.duration else {
            dragStates[index].lifecycle = .finished
            return .finished
        }

        guard let touchLane else {
            return breakDrag(at: index)
        }

        let elapsed = max(time - note.time, 0)
        let spineLane = lane(at: elapsed, for: note)
        guard abs(touchLane - spineLane) <= Window.dragLaneTolerance + Window.comparisonEpsilon else {
            return breakDrag(at: index)
        }

        combo += 1
        maxCombo = max(maxCombo, combo)
        let points = 1 + combo
        addScore(points)
        return .scored(points: points, combo: combo)
    }

    @discardableResult
    func advance(to time: TimeInterval) -> [JudgmentResult] {
        var results: [JudgmentResult] = []

        for index in pendingNotes.indices where !pendingNotes[index].consumed {
            let elapsed = time - pendingNotes[index].note.time
            guard elapsed > Window.bad + Window.comparisonEpsilon else {
                continue
            }

            pendingNotes[index].consumed = true
            results.append(recordMiss())
        }

        for index in dragStates.indices where dragStates[index].lifecycle == .pending {
            let elapsed = time - dragStates[index].note.time
            guard elapsed > Window.bad + Window.comparisonEpsilon else {
                continue
            }

            dragStates[index].lifecycle = .inactive
            results.append(recordMiss())
        }

        return results
    }

    private func award(judgment: Judgment) -> JudgmentResult {
        let basePoints: Int
        let pointsAwarded: Int
        switch judgment {
        case .perfect:
            basePoints = 5
            combo += 1
            maxCombo = max(maxCombo, combo)
            pointsAwarded = basePoints + combo
        case .great:
            basePoints = 3
            combo += 1
            maxCombo = max(maxCombo, combo)
            pointsAwarded = basePoints + combo
        case .good:
            basePoints = 2
            combo = 0
            pointsAwarded = basePoints
        case .bad:
            basePoints = 1
            combo = 0
            pointsAwarded = basePoints
        case .miss:
            return recordMiss()
        }

        addScore(pointsAwarded)
        incrementCount(for: judgment)

        return JudgmentResult(
            judgment: judgment,
            pointsAwarded: pointsAwarded,
            combo: combo,
            score: score
        )
    }

    private func breakDrag(at index: Int) -> DragTickResult {
        dragStates[index].lifecycle = .broken
        _ = recordMiss()
        return .broken
    }

    private func judgment(for offset: TimeInterval) -> Judgment {
        if offset <= Window.perfect + Window.comparisonEpsilon {
            return .perfect
        }
        if offset <= Window.great + Window.comparisonEpsilon {
            return .great
        }
        if offset <= Window.good + Window.comparisonEpsilon {
            return .good
        }
        return .bad
    }

    private func dragStateIndex(for noteID: UUID) -> Int? {
        dragStates.firstIndex { $0.note.id == noteID }
    }

    private func lane(at elapsed: TimeInterval, for note: Note) -> Double {
        var previousOffset: TimeInterval = 0
        var previousLane = note.lane

        for keyframe in note.lanePath {
            let offset = max(keyframe.offset, 0)
            guard offset > previousOffset else {
                previousOffset = offset
                previousLane = keyframe.lane
                continue
            }

            guard elapsed < offset else {
                previousOffset = offset
                previousLane = keyframe.lane
                continue
            }

            let progress = (elapsed - previousOffset) / (offset - previousOffset)
            return previousLane + (keyframe.lane - previousLane) * progress
        }

        return previousLane
    }

    private func nearestUnconsumedNoteIndex(lane: Int, at time: TimeInterval) -> Int? {
        var nearestIndex: Int?
        var nearestDistance = Window.bad + Window.comparisonEpsilon

        for index in pendingNotes.indices where !pendingNotes[index].consumed {
            let note = pendingNotes[index].note
            guard note.lane == Double(lane) else { continue }

            let distance = abs(note.time - time)
            guard distance <= Window.bad + Window.comparisonEpsilon, distance < nearestDistance else {
                continue
            }

            nearestIndex = index
            nearestDistance = distance
        }

        return nearestIndex
    }

    private func incrementCount(for judgment: Judgment) {
        switch judgment {
        case .perfect:
            judgmentCounts.perfect += 1
        case .great:
            judgmentCounts.great += 1
        case .good:
            judgmentCounts.good += 1
        case .bad:
            judgmentCounts.bad += 1
        case .miss:
            judgmentCounts.miss += 1
        }
    }

    private func addScore(_ points: Int) {
        guard points > 0 else { return }

        score += points
        let thresholdsPassed = score / 200
        let newThresholds = thresholdsPassed - scoreThresholdsPassed
        guard newThresholds > 0 else { return }

        scoreThresholdsPassed = thresholdsPassed
        life = min(100, life + newThresholds)
    }

    private func recordMiss() -> JudgmentResult {
        combo = 0
        judgmentCounts.miss += 1
        life = max(0, life - 5)
        if life == 0 {
            isGameOver = true
        }

        return JudgmentResult(
            judgment: .miss,
            pointsAwarded: 0,
            combo: combo,
            score: score
        )
    }
}
