import SwiftUI

struct GameplayContainerView: View {
    private let track: TrackEntity?
    private let difficulty: Difficulty?

    init() {
        track = nil
        difficulty = nil
    }

    init(track: TrackEntity, difficulty: Difficulty) {
        self.track = track
        self.difficulty = difficulty
    }

    var body: some View {
        Text(track.map { "\($0.title) · \(difficulty?.displayName ?? "게임")" } ?? "게임")
            .navigationTitle("게임")
    }
}
