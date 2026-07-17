import AVFoundation
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
                } onRestart: {
                    summary = nil
                    sessionID = UUID()
                } onExit: {
                    dismiss()
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: GameplayViewModel

    private let onComplete: (GameplaySummary) -> Void
    private let onRestart: () -> Void
    private let onExit: () -> Void

    init(
        track: TrackEntity,
        difficulty: Difficulty,
        onComplete: @escaping (GameplaySummary) -> Void,
        onRestart: @escaping () -> Void,
        onExit: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: GameplayViewModel(track: track, difficulty: difficulty)
        )
        self.onComplete = onComplete
        self.onRestart = onRestart
        self.onExit = onExit
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                Color.black
            case .ready:
                gameplayContent
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
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            viewModel.pause()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: AVAudioSession.interruptionNotification
        )) { notification in
            guard
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                AVAudioSession.InterruptionType(rawValue: rawType) == .began
            else { return }
            viewModel.pause()
        }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var gameplayContent: some View {
        if let scene = viewModel.scene {
            ZStack(alignment: .topTrailing) {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])

                if !viewModel.isPaused {
                    Button {
                        viewModel.pause()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.headline)
                            .padding(12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.65))
                    .accessibilityLabel("일시정지")
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                }

                if viewModel.isPaused {
                    pauseOverlay
                }
            }
        } else {
            Color.black
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                if let countdown = viewModel.countdown {
                    Text("\(countdown)")
                        .font(.system(size: 88, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .accessibilityLabel("\(countdown)초 후 재개")
                } else {
                    Text("일시정지")
                        .font(.largeTitle.bold())

                    VStack(spacing: 12) {
                        Button("계속하기") {
                            viewModel.resume()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("다시하기", action: onRestart)
                            .buttonStyle(.bordered)

                        Button("나가기", action: onExit)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }
}
