import Foundation

enum Judgment: Equatable, Sendable {
    case perfect
    case great
    case good
    case miss
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

    private enum Window {
        static let perfect: TimeInterval = 0.050
        static let great: TimeInterval = 0.100
        static let good: TimeInterval = 0.150
        static let comparisonEpsilon: TimeInterval = 0.000_000_001
    }

    private var pendingNotes: [PendingNote]

    private(set) var score = 0
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var judgmentCounts = JudgmentCounts()

    init(notes: [Note]) {
        pendingNotes = notes
            .filter { $0.kind == .tap }
            .sorted { $0.time < $1.time }
            .map { PendingNote(note: $0) }
    }

    @discardableResult
    func tap(lane: Int, at time: TimeInterval) -> JudgmentResult? {
        guard let index = nearestUnconsumedNoteIndex(lane: lane, at: time) else {
            return nil
        }

        pendingNotes[index].consumed = true
        let offset = abs(pendingNotes[index].note.time - time)
        let judgment: Judgment
        let basePoints: Int

        if offset <= Window.perfect + Window.comparisonEpsilon {
            judgment = .perfect
            basePoints = 100
        } else if offset <= Window.great + Window.comparisonEpsilon {
            judgment = .great
            basePoints = 70
        } else {
            judgment = .good
            basePoints = 40
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

        return results
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
