import Foundation
import OSLog
import SwiftData

/// Removes a track from the library: the SwiftData row (beatmaps and score
/// records follow via `.cascade` delete rules on `TrackEntity`) plus the
/// app-owned imported audio copy under Application Support/AudioFiles.
enum TrackDeletionService {
    private static let logger = Logger(
        subsystem: "com.skier.autowave",
        category: "TrackDeletion"
    )

    /// Deletes `track` and saves. Audio-file removal is best-effort and never
    /// fails the deletion — a missing or locked file is logged and ignored.
    @MainActor
    static func delete(_ track: TrackEntity, in context: ModelContext) throws {
        // Resolve the file location before the row is invalidated.
        let audioURL = track.audioURL

        context.delete(track)
        try context.save()

        removeAudioFile(at: audioURL)
    }

    private static func removeAudioFile(at audioURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: audioURL.path) else { return }

        do {
            try fileManager.removeItem(at: audioURL)
        } catch {
            logger.error(
                "오디오 파일 삭제 실패: \(audioURL.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
