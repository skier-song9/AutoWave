import Foundation
import SwiftData

@Model
final class BeatmapEntity {
    var difficulty: String
    @Attribute(.externalStorage)
    var beatmapData: Data
    var track: TrackEntity

    init(difficulty: String, beatmapData: Data, track: TrackEntity) {
        self.difficulty = difficulty
        self.beatmapData = beatmapData
        self.track = track
    }
}
