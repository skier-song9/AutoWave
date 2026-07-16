import SwiftData
import SwiftUI

@main
struct AutoWaveApp: App {
    private let modelContainer: ModelContainer

    init() {
        modelContainer = try! ModelContainer(
            for: Schema([]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
