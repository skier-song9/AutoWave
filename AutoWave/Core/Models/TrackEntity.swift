import Foundation
import SwiftData

@Model
final class TrackEntity {
    var title: String
    var sourceFilename: String
    var importedAt: Date
    var relativeAudioPath: String
    var duration: TimeInterval = 0
    var analysisData: Data? = nil

    @Relationship(deleteRule: .cascade, inverse: \BeatmapEntity.track)
    var beatmaps: [BeatmapEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \ScoreRecord.track)
    var scoreRecords: [ScoreRecord] = []

    var audioURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupportURL.appendingPathComponent(relativeAudioPath)
    }

    init(
        title: String,
        sourceFilename: String,
        importedAt: Date,
        relativeAudioPath: String,
        duration: TimeInterval = 0,
        analysisData: Data? = nil
    ) {
        self.title = title
        self.sourceFilename = sourceFilename
        self.importedAt = importedAt
        self.relativeAudioPath = relativeAudioPath
        self.duration = duration
        self.analysisData = analysisData
    }
}
