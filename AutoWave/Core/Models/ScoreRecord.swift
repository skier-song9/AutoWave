import Foundation
import SwiftData

@Model
final class ScoreRecord {
    var track: TrackEntity
    var difficulty: String
    var score: Int
    var maxCombo: Int
    var playedAt: Date

    init(
        track: TrackEntity,
        difficulty: String,
        score: Int,
        maxCombo: Int,
        playedAt: Date
    ) {
        self.track = track
        self.difficulty = difficulty
        self.score = score
        self.maxCombo = maxCombo
        self.playedAt = playedAt
    }
}
