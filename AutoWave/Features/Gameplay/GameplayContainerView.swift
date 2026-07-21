import AVFoundation
import SpriteKit
import SwiftData
import SwiftUI
import UIKit

struct GameplayContainerView: View {
    @Environment(\.dismiss) private var dismiss

    private let track: TrackEntity?
    private let difficulty: Difficulty?
    private let noteSpeedState: NoteSpeedMultiplierState

    @State private var sessionID = UUID()
    @State private var summary: GameplaySummary?

    init() {
        track = nil
        difficulty = nil
        noteSpeedState = NoteSpeedMultiplierState()
    }

    init(
        track: TrackEntity,
        difficulty: Difficulty,
        noteSpeedState: NoteSpeedMultiplierState = NoteSpeedMultiplierState()
    ) {
        self.track = track
        self.difficulty = difficulty
        self.noteSpeedState = noteSpeedState
    }

    var body: some View {
        Group {
            if let track, let difficulty {
                GameplaySessionView(
                    track: track,
                    difficulty: difficulty,
                    noteSpeedState: noteSpeedState
                ) { result in
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
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .navigationTitle("게임")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
}

private struct InteractivePopGestureBlocker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) { }

    static func dismantleUIViewController(_ uiViewController: Controller, coordinator: ()) {
        uiViewController.setInteractivePopGestureEnabled(true)
    }

    final class Controller: UIViewController {
        override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
            [.bottom]
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            setInteractivePopGestureEnabled(false)
            parent?.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        }

        override func viewWillDisappear(_ animated: Bool) {
            setInteractivePopGestureEnabled(true)
            super.viewWillDisappear(animated)
        }

        fileprivate func setInteractivePopGestureEnabled(_ isEnabled: Bool) {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = isEnabled
        }
    }
}

@MainActor
private struct GameplaySessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: GameplayViewModel
    @State private var isPauseMenuPresented = false
    @State private var speedFlash = false

    private let onComplete: (GameplaySummary) -> Void
    private let onRestart: () -> Void
    private let onExit: () -> Void

    init(
        track: TrackEntity,
        difficulty: Difficulty,
        noteSpeedState: NoteSpeedMultiplierState,
        onComplete: @escaping (GameplaySummary) -> Void,
        onRestart: @escaping () -> Void,
        onExit: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: GameplayViewModel(
                track: track,
                difficulty: difficulty,
                noteSpeedState: noteSpeedState
            )
        )
        self.onComplete = onComplete
        self.onRestart = onRestart
        self.onExit = onExit
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                AppTheme.background
            case .ready:
                gameplayContent
            case .failed(let message):
                VStack(spacing: 16) {
                    Text(message)
                        .foregroundStyle(AppTheme.text)
                    Text("라이브러리로 돌아가 다시 시도해 주세요.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedBright)
                    Button("라이브러리로", action: onExit)
                        .buttonStyle(GradientCTAButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
            case .completed:
                AppTheme.background
            }
        }
        .task {
            viewModel.start(context: modelContext, onComplete: onComplete)
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .inactive || phase == .background else { return }
            pauseGame()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: AVAudioSession.interruptionNotification
        )) { notification in
            guard
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                AVAudioSession.InterruptionType(rawValue: rawType) == .began
            else { return }
            pauseGame()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willResignActiveNotification
        )) { _ in
            pauseGame()
        }
        .onChange(of: viewModel.isPaused) { _, isPaused in
            if !isPaused, viewModel.countdown == nil {
                isPauseMenuPresented = false
            }
        }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var gameplayContent: some View {
        if let scene = viewModel.scene {
            ZStack(alignment: .topTrailing) {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                    .zIndex(0)

                if !isPauseMenuPresented && !viewModel.isPaused {
                    VStack(alignment: .trailing, spacing: 8) {
                        speedControl
                        pauseButton
                    }
                    .safeAreaPadding(.top, 18)
                    .safeAreaPadding(.trailing, 18)
                    .zIndex(20)
                    .allowsHitTesting(true)
                }
            }
            .overlay {
                if isPauseMenuPresented || viewModel.isPaused {
                    pauseOverlay
                }
            }
            .background(InteractivePopGestureBlocker().allowsHitTesting(false))
        } else {
            AppTheme.background
        }
    }

    private var pauseButton: some View {
        CircleIconButton(systemName: "pause.fill", compact: true) {
            pauseGame()
        }
        .accessibilityLabel("일시정지")
        .contentShape(Rectangle())
        .frame(width: 72, height: 72)
    }

    private var speedControl: some View {
        CircleIconButton(systemName: "speedometer", compact: true) {
            cycleSpeed()
        }
        .accessibilityLabel("노트 배속 변경")
        .accessibilityValue(speedLabel(viewModel.noteSpeedMultiplier))
        .frame(width: 72, height: 72)
        .contentShape(Rectangle())
        .background(
            Circle()
                .fill(speedFlash ? AppTheme.accentPurple.opacity(0.28) : Color.clear)
        )
        .scaleEffect(speedFlash ? 1.08 : 1)
        .animation(.easeOut(duration: 0.16), value: speedFlash)
        .zIndex(21)
        .allowsHitTesting(true)
    }

    private var pauseOverlay: some View {
        ZStack {
            AppTheme.background.opacity(0.68)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                if let countdown = viewModel.countdown {
                    Text("\(countdown)")
                        .font(.system(size: 88, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.text)
                        .accessibilityLabel("\(countdown)초 후 재개")
                } else {
                    Text("일시정지")
                        .font(.largeTitle.bold())

                    VStack(spacing: 12) {
                        Button("계속하기") {
                            viewModel.resume()
                        }
                        .buttonStyle(GradientCTAButtonStyle())
                        .frame(maxWidth: .infinity)

                        Button("다시하기", action: onRestart)
                            .buttonStyle(GradientCTAButtonStyle(secondary: true))
                            .frame(maxWidth: .infinity)

                        Button("나가기", action: onExit)
                            .buttonStyle(GradientCTAButtonStyle(secondary: true))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(AppTheme.backgroundElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppTheme.accentGradient, lineWidth: 1.5)
            }
            .shadow(color: AppTheme.accentPurple.opacity(0.45), radius: 22)
            .foregroundStyle(AppTheme.text)
        }
    }

    private func pauseGame() {
        guard viewModel.state == .ready else { return }
        viewModel.pause()
        isPauseMenuPresented = viewModel.isPaused
    }

    private func cycleSpeed() {
        viewModel.cycleNoteSpeedMultiplier(in: modelContext)
        withAnimation(.easeOut(duration: 0.12)) {
            speedFlash = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.22)) {
                speedFlash = false
            }
        }
    }

    private func speedLabel(_ value: CGFloat) -> String {
        String(format: "x%.2f", Double(value))
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }
}
