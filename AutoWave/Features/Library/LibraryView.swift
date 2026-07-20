import Foundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrackEntity.importedAt, order: .reverse) private var tracks: [TrackEntity]
    @State private var errorMessage: String?
    @State private var pendingDeleteTrack: TrackEntity?
    @State private var pendingRetryTrack: TrackEntity?
    @State private var retryTrack: TrackEntity?
    @State private var readyTrack: TrackEntity?
    @State private var gameplayTrack: TrackEntity?
    @State private var gameplayDifficulty: Difficulty?
    @State private var noteSpeedState = NoteSpeedMultiplierState()

    var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView {
                    Label("라이브러리가 비어 있어요", systemImage: "water.waves")
                } description: {
                    Text("음원을 가져와서 나만의 리듬게임을 만들어보세요")
                } actions: {
                    NavigationLink {
                        ImportView()
                    } label: {
                        Text("음원 가져오기")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(tracks) { track in
                        Group {
                            trackEntry(for: track)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDeleteTrack = track
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                pendingRetryTrack = track
                            } label: {
                                Label("다시 변환", systemImage: "arrow.clockwise")
                            }

                            Button(role: .destructive) {
                                pendingDeleteTrack = track
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(AppTheme.panel)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(AppTheme.line, lineWidth: 1)
                                }
                                .padding(.vertical, 4)
                        )
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .appScreenBackground()
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .navigationTitle("라이브러리")
        .navigationDestination(
            isPresented: Binding(
                get: { gameplayTrack != nil && gameplayDifficulty != nil },
                set: {
                    if !$0 {
                        gameplayTrack = nil
                        gameplayDifficulty = nil
                    }
                }
            )
        ) {
            if let gameplayTrack, let gameplayDifficulty {
                GameplayContainerView(
                    track: gameplayTrack,
                    difficulty: gameplayDifficulty,
                    noteSpeedState: noteSpeedState
                )
            }
        }
        .navigationDestination(
            isPresented: Binding(
                get: { retryTrack != nil },
                set: { if !$0 { retryTrack = nil } }
            )
        ) {
            if let retryTrack {
                AnalysisView(track: retryTrack)
            }
        }
        .confirmationDialog(
            "정말 삭제할까요?",
            isPresented: Binding(
                get: { pendingDeleteTrack != nil },
                set: { if !$0 { pendingDeleteTrack = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                guard let track = pendingDeleteTrack else { return }
                pendingDeleteTrack = nil
                delete(track)
            }
            Button("취소", role: .cancel) { pendingDeleteTrack = nil }
        }
        .confirmationDialog(
            "다시 변환할까요?",
            isPresented: Binding(
                get: { pendingRetryTrack != nil },
                set: { if !$0 { pendingRetryTrack = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("다시 변환") {
                guard let track = pendingRetryTrack else { return }
                pendingRetryTrack = nil
                retryConversion(track)
            }
            Button("취소", role: .cancel) { pendingRetryTrack = nil }
        }
        .alert("라이브러리 오류", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
                Text(errorMessage ?? "알 수 없는 오류")
        }
        .sheet(
            isPresented: Binding(
                get: { readyTrack != nil },
                set: { if !$0 { readyTrack = nil } }
            )
        ) {
            if let readyTrack {
                ReadySheetView(
                    track: readyTrack,
                    difficulty: .normal,
                    speedState: noteSpeedState
                ) { difficulty in
                    gameplayTrack = readyTrack
                    gameplayDifficulty = difficulty
                    self.readyTrack = nil
                }
            }
        }
    }

    @ViewBuilder
    private func trackEntry(for track: TrackEntity) -> some View {
        if track.beatmaps.isEmpty {
            NavigationLink {
                AnalysisView(track: track)
            } label: {
                TrackRow(track: track)
            }
        } else {
            Button {
                readyTrack = track
            } label: {
                TrackRow(track: track)
            }
            .buttonStyle(.plain)
            .accessibilityHint("준비 화면 열기")
        }
    }

    private func delete(_ track: TrackEntity) {
        let audioURL = track.audioURL
        modelContext.delete(track)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "음원을 삭제하지 못했어요. 다시 시도해 주세요."
            return
        }

        if FileManager.default.fileExists(atPath: audioURL.path) {
            do {
                try FileManager.default.removeItem(at: audioURL)
            } catch {
                errorMessage = "음원 파일을 삭제하지 못했어요."
            }
        }
    }

    private func retryConversion(_ track: TrackEntity) {
        do {
            try AnalysisViewModel.resetConversion(for: track, in: modelContext)
            retryTrack = track
        } catch {
            errorMessage = "다시 변환을 시작하지 못했어요. 다시 시도해 주세요."
        }
    }
}

private struct TrackRow: View {
    let track: TrackEntity

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(trackColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(track.title)
                        .font(.headline)
                    Spacer()
                    Text(formattedDuration(track.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    ForEach(
                        Difficulty.allCases.filter { difficulty in
                            track.beatmaps.contains { $0.difficulty == difficulty.rawValue }
                        },
                        id: \.rawValue
                    ) { difficulty in
                        Text(difficulty.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(trackColor.opacity(0.15), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(trackColor.opacity(0.4), lineWidth: 0.5)
                            }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var trackColor: Color {
        guard let beatmapEntity = track.beatmaps.first,
              let beatmap = try? JSONDecoder().decode(
                  Beatmap.self,
                  from: beatmapEntity.beatmapData
              ) else {
            return .accentColor
        }
        return beatmap.palette.color
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

@MainActor
private struct ReadySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let track: TrackEntity
    let initialDifficulty: Difficulty
    let speedState: NoteSpeedMultiplierState
    let onStart: (Difficulty) -> Void

    @State private var selectedDifficulty: Difficulty
    @State private var laneCount = 4
    @State private var speedStateRevision = 0
    @State private var speedFlash = false
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var viewModel = AnalysisViewModel()

    init(
        track: TrackEntity,
        difficulty: Difficulty,
        speedState: NoteSpeedMultiplierState,
        onStart: @escaping (Difficulty) -> Void
    ) {
        self.track = track
        initialDifficulty = difficulty
        self.speedState = speedState
        self.onStart = onStart
        _selectedDifficulty = State(initialValue: difficulty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("준비")
                            .font(.largeTitle.bold())
                        Text(track.title)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("난이도")
                            .font(.headline)
                        Picker("난이도", selection: $selectedDifficulty) {
                            ForEach(Difficulty.allCases, id: \.rawValue) { difficulty in
                                Text(difficulty.displayName).tag(difficulty)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    settingRow(title: "레인 수") {
                        Stepper("\(laneCount)", value: $laneCount, in: 4...7)
                            .labelsHidden()
                        Text("\(laneCount)")
                            .font(.title3.monospacedDigit())
                            .frame(minWidth: 28)
                    }

                    settingRow(title: "배속") {
                        Button {
                            cycleSpeed()
                        } label: {
                            Text(speedLabel(Double(speedState.value)))
                                .font(.headline.monospacedDigit())
                                .frame(minWidth: 86)
                                .id(speedStateRevision)
                        }
                        .buttonStyle(.borderedProminent)
                        .scaleEffect(speedFlash ? 1.08 : 1)
                        .animation(.easeOut(duration: 0.16), value: speedFlash)
                    }

                    if isStarting {
                        ProgressView("비트맵 준비 중…")
                            .frame(maxWidth: .infinity)
                    } else {
                        Button("시작") {
                            startGame()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .appScreenBackground()
            .navigationTitle("준비")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .task {
            let profile = ProfileEntity.current(in: modelContext)
            laneCount = min(max(
                profile.preferredLaneCount ?? DifficultyProfile.profile(for: initialDifficulty).laneCount,
                4
            ), 7)
            let speedMultiplier = NoteSpeedMultiplierState.allowedValues.first {
                abs(Double($0) - profile.noteSpeedMultiplier) < 0.000_001
            } ?? 1.0
            speedState.set(speedMultiplier)
            speedStateRevision &+= 1
        }
        .alert("준비 오류", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "알 수 없는 오류")
        }
    }

    private func settingRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            content()
        }
    }

    private func cycleSpeed() {
        let next = Double(speedState.cycle())
        speedStateRevision &+= 1
        flashSpeedControl()
        let profile = ProfileEntity.current(in: modelContext)
        profile.noteSpeedMultiplier = next
        do {
            try modelContext.save()
        } catch {
            errorMessage = "배속 설정을 저장하지 못했어요."
        }
    }

    private func flashSpeedControl() {
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

    private func startGame() {
        guard !isStarting else { return }
        isStarting = true

        let profile = ProfileEntity.current(in: modelContext)
        profile.preferredLaneCount = laneCount
        profile.noteSpeedMultiplier = Double(speedState.value)

        do {
            try modelContext.save()
        } catch {
            isStarting = false
            errorMessage = "설정을 저장하지 못했어요. 다시 시도해 주세요."
            return
        }

        let storedBeatmap = track.beatmaps.first {
            $0.difficulty == selectedDifficulty.rawValue
        }.flatMap {
            try? JSONDecoder().decode(Beatmap.self, from: $0.beatmapData)
        }
        let shouldRegenerate = AnalysisViewModel.shouldRegenerate(
            storedLaneCount: storedBeatmap?.laneCount,
            chosenLaneCount: laneCount,
            storedGeneratorVersion: storedBeatmap?.generatorVersion
        )

        guard shouldRegenerate else {
            isStarting = false
            onStart(selectedDifficulty)
            dismiss()
            return
        }

        Task { @MainActor in
            await viewModel.regenerate(
                track: track,
                difficulty: selectedDifficulty,
                laneCountOverride: laneCount,
                context: modelContext
            )
            guard case .done = viewModel.state else {
                isStarting = false
                errorMessage = "비트맵을 준비하지 못했어요. 다시 시도해 주세요."
                return
            }
            isStarting = false
            onStart(selectedDifficulty)
            dismiss()
        }
    }

    private func speedLabel(_ value: Double) -> String {
        String(format: "x%.2f", value)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }
}

private extension Difficulty {
    var tint: Color {
        switch self {
        case .heaven:
            .cyan
        case .easy:
            .green
        case .normal:
            .blue
        case .hard:
            .orange
        case .hell:
            .red
        }
    }
}
