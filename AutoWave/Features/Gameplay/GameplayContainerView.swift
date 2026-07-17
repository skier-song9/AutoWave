import SpriteKit
import SwiftData
import SwiftUI
import UIKit

struct GameplayContainerView: View {
    @Environment(\.dismiss) private var dismiss

    private let track: TrackEntity?
    private let difficulty: Difficulty?

    @State private var sessionID = UUID()
    @State private var summary: GameplaySummary?

    init() {
        track = nil
        difficulty = nil
    }

    init(track: TrackEntity, difficulty: Difficulty) {
        self.track = track
        self.difficulty = difficulty
    }

    var body: some View {
        Group {
            if let track, let difficulty {
                GameplaySessionView(track: track, difficulty: difficulty) { result in
                    summary = result
                }
                .id(sessionID)
                .ignoresSafeArea()
            } else {
                Text("게임을 시작할 음원을 선택해 주세요.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("게임")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            requestOrientation(.landscape)
        }
        .onDisappear {
            requestOrientation(.all)
        }
        .fullScreenCover(item: $summary) { result in
            if let track, let difficulty {
                ResultsView(
                    summary: result,
                    trackTitle: track.title,
                    difficulty: difficulty,
                    onRestart: {
                        summary = nil
                        sessionID = UUID()
                    },
                    onLibrary: {
                        summary = nil
                        dismiss()
                    }
                )
            }
        }
    }

    private func requestOrientation(_ orientations: UIInterfaceOrientationMask) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: orientations)
        )
    }
}

@MainActor
private struct GameplaySessionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: GameplayViewModel

    private let onComplete: (GameplaySummary) -> Void

    init(
        track: TrackEntity,
        difficulty: Difficulty,
        onComplete: @escaping (GameplaySummary) -> Void
    ) {
        _viewModel = State(
            initialValue: GameplayViewModel(track: track, difficulty: difficulty)
        )
        self.onComplete = onComplete
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                Color.black
            case .ready:
                if let scene = viewModel.scene {
                    SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                } else {
                    Color.black
                }
            case .failed(let message):
                VStack(spacing: 16) {
                    Text(message)
                        .foregroundStyle(.white)
                    Text("라이브러리로 돌아가 다시 시도해 주세요.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            case .completed:
                Color.black
            }
        }
        .task {
            viewModel.start(context: modelContext, onComplete: onComplete)
        }
        .onDisappear {
            viewModel.stop()
        }
        .statusBarHidden(true)
    }
}
