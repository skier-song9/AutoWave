struct DifficultyProfile: Sendable {
    var laneCount: Int
    var maxNotesPerSecond: Double
    var strengthPercentile: Double
    var maxSimultaneous: Int
    var dragRatio: Double
    var movingDragRatio: Double
    var scrollSpeed: Double

    static func profile(for difficulty: Difficulty) -> DifficultyProfile {
        switch difficulty {
        case .heaven:
            DifficultyProfile(
                laneCount: 4,
                maxNotesPerSecond: 1.2,
                strengthPercentile: 80,
                maxSimultaneous: 1,
                dragRatio: 0.10,
                movingDragRatio: 0.0,
                scrollSpeed: 260
            )
        case .easy:
            DifficultyProfile(
                laneCount: 4,
                maxNotesPerSecond: 2.4,
                strengthPercentile: 60,
                maxSimultaneous: 1,
                dragRatio: 0.15,
                movingDragRatio: 0.2,
                scrollSpeed: 330
            )
        case .normal:
            DifficultyProfile(
                laneCount: 5,
                maxNotesPerSecond: 4.0,
                strengthPercentile: 40,
                maxSimultaneous: 2,
                dragRatio: 0.20,
                movingDragRatio: 0.4,
                scrollSpeed: 420
            )
        case .hard:
            DifficultyProfile(
                laneCount: 6,
                maxNotesPerSecond: 6.5,
                strengthPercentile: 20,
                maxSimultaneous: 2,
                dragRatio: 0.25,
                movingDragRatio: 0.6,
                scrollSpeed: 520
            )
        case .hell:
            DifficultyProfile(
                laneCount: 7,
                maxNotesPerSecond: 9.5,
                strengthPercentile: 8,
                maxSimultaneous: 3,
                dragRatio: 0.30,
                movingDragRatio: 0.8,
                scrollSpeed: 640
            )
        }
    }
}
