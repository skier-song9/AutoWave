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
        let schema = Schema([TrackEntity.self, BeatmapEntity.self, ScoreRecord.self])

        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema)]
            )
        } catch {
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [
                        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    ]
                )
            } catch {
                fatalError("Unable to create the SwiftData model container: \(error)")
            }
        }
    }
}
