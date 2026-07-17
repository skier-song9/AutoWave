import SwiftUI

struct AnalysisView: View {
    private let track: TrackEntity?

    init() {
        track = nil
    }

    init(track: TrackEntity) {
        self.track = track
    }

    var body: some View {
        Text(track.map { "\($0.title) 변환 준비 중" } ?? "변환")
            .navigationTitle("변환")
    }
}
