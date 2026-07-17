import AVFoundation
import Foundation
import SwiftData

enum AudioImportError: LocalizedError {
    case sourceFileMissing
    case invalidDuration

    var errorDescription: String? {
        switch self {
        case .sourceFileMissing:
            "선택한 파일을 찾을 수 없습니다."
        case .invalidDuration:
            "음원 길이를 읽을 수 없습니다."
        }
    }
}

enum AudioImportService {
    @MainActor
    static func importAudio(from url: URL, into context: ModelContext) async throws -> TrackEntity {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioImportError.sourceFileMissing
        }

        let applicationSupportURL = try applicationSupportDirectory()
        let audioFilesURL = applicationSupportURL.appendingPathComponent("AudioFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: audioFilesURL, withIntermediateDirectories: true)

        let fileExtension = url.pathExtension.isEmpty ? "audio" : url.pathExtension
        let relativeAudioPath = "AudioFiles/\(UUID().uuidString).\(fileExtension)"
        let destinationURL = applicationSupportURL.appendingPathComponent(relativeAudioPath)

        try FileManager.default.copyItem(at: url, to: destinationURL)

        do {
            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            guard duration.isFinite, duration >= 0 else {
                throw AudioImportError.invalidDuration
            }

            let track = TrackEntity(
                title: url.deletingPathExtension().lastPathComponent,
                sourceFilename: url.lastPathComponent,
                importedAt: Date(),
                relativeAudioPath: relativeAudioPath,
                duration: duration
            )
            context.insert(track)
            try context.save()
            return track
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    private static func applicationSupportDirectory() throws -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        try FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        return applicationSupportURL
    }
}
