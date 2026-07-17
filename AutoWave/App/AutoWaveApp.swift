import SwiftData
import SwiftUI

@main
struct AutoWaveApp: App {
    private let modelContainer: ModelContainer

    init() {
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            let applicationSupportURL = try ensureApplicationSupportDirectory()
            let schema = Schema([
                TrackEntity.self,
                BeatmapEntity.self,
                ScoreRecord.self,
                ProfileEntity.self
            ])
            return try ModelContainer(
                for: schema,
                configurations: [
                    ModelConfiguration(schema: schema, url: applicationSupportURL.appendingPathComponent("AutoWave.store"))
                ]
            )
        } catch {
            fatalError("Unable to create the SwiftData model container: \(error)")
        }
    }

    private static func ensureApplicationSupportDirectory() throws -> URL {
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
