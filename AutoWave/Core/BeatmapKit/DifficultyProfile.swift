struct DifficultyProfile: Sendable {
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
                maxNotesPerSecond: 0.8,
                strengthPercentile: 85,
                maxSimultaneous: 1,
                dragRatio: 0.10,
                movingDragRatio: 0.0,
                scrollSpeed: 250
            )
        case .easy:
            DifficultyProfile(
                maxNotesPerSecond: 1.5,
                strengthPercentile: 65,
                maxSimultaneous: 1,
                dragRatio: 0.15,
                movingDragRatio: 0.2,
                scrollSpeed: 320
            )
        case .normal:
            DifficultyProfile(
                maxNotesPerSecond: 2.5,
                strengthPercentile: 45,
                maxSimultaneous: 1,
                dragRatio: 0.20,
                movingDragRatio: 0.4,
                scrollSpeed: 400
            )
        case .hard:
            DifficultyProfile(
                maxNotesPerSecond: 4.0,
                strengthPercentile: 25,
                maxSimultaneous: 2,
                dragRatio: 0.25,
                movingDragRatio: 0.6,
                scrollSpeed: 500
            )
        case .hell:
            DifficultyProfile(
                maxNotesPerSecond: 6.0,
                strengthPercentile: 10,
                maxSimultaneous: 2,
                dragRatio: 0.30,
                movingDragRatio: 0.8,
                scrollSpeed: 620
            )
        }
    }
}
