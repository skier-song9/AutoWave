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
                maxNotesPerSecond: 2.4,
                strengthPercentile: 55,
                maxSimultaneous: 2,
                dragRatio: 0.20,
                movingDragRatio: 0.2,
                scrollSpeed: 220
            )
        case .easy:
            DifficultyProfile(
                laneCount: 4,
                maxNotesPerSecond: 4,
                strengthPercentile: 35,
                maxSimultaneous: 2,
                dragRatio: 0.30,
                movingDragRatio: 0.3,
                scrollSpeed: 280
            )
        case .normal:
            DifficultyProfile(
                laneCount: 5,
                maxNotesPerSecond: 6,
                strengthPercentile: 20,
                maxSimultaneous: 2,
                dragRatio: 0.40,
                movingDragRatio: 0.5,
                scrollSpeed: 360
            )
        case .hard:
            DifficultyProfile(
                laneCount: 6,
                maxNotesPerSecond: 8.5,
                strengthPercentile: 10,
                maxSimultaneous: 2,
                dragRatio: 0.50,
                movingDragRatio: 0.7,
                scrollSpeed: 440
            )
        case .hell:
            DifficultyProfile(
                laneCount: 7,
                maxNotesPerSecond: 12,
                strengthPercentile: 5,
                maxSimultaneous: 2,
                dragRatio: 0.60,
                movingDragRatio: 0.9,
                scrollSpeed: 545
            )
        }
    }
}
