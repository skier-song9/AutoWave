import Foundation

enum Judgment: Equatable, Sendable {
    case perfect
    case great
    case good
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
    var miss = 0
}

final class JudgmentEngine {
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
        static let perfect: TimeInterval = 0.050
        static let great: TimeInterval = 0.100
        static let good: TimeInterval = 0.150
        static let comparisonEpsilon: TimeInterval = 0.000_000_001
        static let dragLaneTolerance = 0.6
    }

    private var pendingNotes: [PendingNote]
    private var dragStates: [DragState]

    private(set) var score = 0
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var judgmentCounts = JudgmentCounts()

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
        guard timeOffset <= Window.good + Window.comparisonEpsilon else {
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

        let comboBeforeTick = combo
        combo += 1
        maxCombo = max(maxCombo, combo)
        let points = Int(
            10 * (1 + Double(min(comboBeforeTick, 100)) / 100)
        )
        score += points
        return .scored(points: points, combo: combo)
    }

    @discardableResult
    func advance(to time: TimeInterval) -> [JudgmentResult] {
        var results: [JudgmentResult] = []

        for index in pendingNotes.indices where !pendingNotes[index].consumed {
            let elapsed = time - pendingNotes[index].note.time
            guard elapsed > Window.good else {
                continue
            }

            pendingNotes[index].consumed = true
            combo = 0
            judgmentCounts.miss += 1
            results.append(
                JudgmentResult(
                    judgment: .miss,
                    pointsAwarded: 0,
                    combo: combo,
                    score: score
                )
            )
        }

        for index in dragStates.indices where dragStates[index].lifecycle == .pending {
            let elapsed = time - dragStates[index].note.time
            guard elapsed > Window.good else {
                continue
            }

            dragStates[index].lifecycle = .inactive
            combo = 0
            judgmentCounts.miss += 1
            results.append(
                JudgmentResult(
                    judgment: .miss,
                    pointsAwarded: 0,
                    combo: combo,
                    score: score
                )
            )
        }

        return results
    }

    private func award(judgment: Judgment) -> JudgmentResult {
        let basePoints: Int
        switch judgment {
        case .perfect:
            basePoints = 100
        case .great:
            basePoints = 70
        case .good:
            basePoints = 40
        case .miss:
            basePoints = 0
        }

        let comboBeforeHit = combo
        combo += 1
        maxCombo = max(maxCombo, combo)
        let pointsAwarded = Int(
            Double(basePoints) * (1 + Double(min(comboBeforeHit, 100)) / 100)
        )
        score += pointsAwarded
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
        combo = 0
        judgmentCounts.miss += 1
        return .broken
    }

    private func judgment(for offset: TimeInterval) -> Judgment {
        if offset <= Window.perfect + Window.comparisonEpsilon {
            return .perfect
        }
        if offset <= Window.great + Window.comparisonEpsilon {
            return .great
        }
        return .good
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
        var nearestDistance = Window.good + Window.comparisonEpsilon

        for index in pendingNotes.indices where !pendingNotes[index].consumed {
            let note = pendingNotes[index].note
            guard note.lane == Double(lane) else { continue }

            let distance = abs(note.time - time)
            guard distance <= Window.good + Window.comparisonEpsilon, distance < nearestDistance else {
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
        case .miss:
            judgmentCounts.miss += 1
        }
    }
}
