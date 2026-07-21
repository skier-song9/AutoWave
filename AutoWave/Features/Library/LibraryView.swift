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
                    .buttonStyle(GradientCTAButtonStyle())
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
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.panel)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                ReadyModal(
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
                        .foregroundStyle(AppTheme.muted)
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
                            .foregroundStyle(difficulty.tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(difficulty.tint.opacity(0.15), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(difficulty.tint.opacity(0.54), lineWidth: 1)
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
            return AppTheme.accentPurple
        }
        return beatmap.palette.color
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

@MainActor
struct ReadyModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let track: TrackEntity
    let initialDifficulty: Difficulty
    let speedState: NoteSpeedMultiplierState
    let onStart: (Difficulty) -> Void

    @State private var selectedDifficulty: Difficulty
    @State private var laneCount = 4
    @State private var speedStateRevision = 0
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
        GeometryReader { proxy in
            let cardWidth = min(proxy.size.width * 0.85, 760)
            let cardHeight = min(proxy.size.height * 0.85, 340)

            ZStack {
                Color.black.opacity(0.68)
                    .ignoresSafeArea()

                HStack(alignment: .top, spacing: 14) {
                    albumPanel
                        .frame(width: min(max(cardWidth * 0.27, 170), 195))

                    ScrollView(.vertical, showsIndicators: false) {
                        settingsColumn
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(14)
                .frame(width: cardWidth, height: cardHeight)
                .background(AppTheme.backgroundElevated, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(AppTheme.accentGradient, lineWidth: 1.5)
                }
                .shadow(color: AppTheme.accentPurple.opacity(0.34), radius: 28)
                .shadow(color: AppTheme.accentBlue.opacity(0.18), radius: 36)
                .overlay(alignment: .topTrailing) {
                    CircleIconButton(systemName: "xmark", compact: true) {
                        dismiss()
                    }
                    .padding(7)
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

    private var albumPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [trackColor, AppTheme.accentPurple, AppTheme.background],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .stroke(AppTheme.text.opacity(0.18), lineWidth: 1)
                        .padding(18)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.backgroundElevated, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(AppTheme.accentGradient, lineWidth: 2)
                        }
                        .padding(12)
                }
                .frame(height: 112)
                .shadow(color: AppTheme.accentPurple.opacity(0.35), radius: 12)

            Text(track.title)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .padding(.top, 9)
            Text("로컬 음원 · \(formattedDuration(track.duration))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppTheme.mutedBright)
                .padding(.top, 4)
        }
        .padding(9)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.line, lineWidth: 1)
        }
    }

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsPanel(title: "난이도") {
                HStack(spacing: 5) {
                    ForEach(Difficulty.allCases, id: \.rawValue) { difficulty in
                        difficultyCard(difficulty)
                    }
                }
            }

            settingsPanel {
                settingCopy(
                    title: "LANE 개수",
                    caption: "노트가 떨어지는 라인의 개수를 설정합니다."
                )
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    ForEach(4...7, id: \.self) { value in
                        optionChip("\(value)", selected: laneCount == value, size: 32) {
                            laneCount = value
                        }
                    }
                }
            }

            settingsPanel {
                settingCopy(
                    title: "배속",
                    caption: "게임 속도를 설정합니다."
                )
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    ForEach(NoteSpeedMultiplierState.allowedValues, id: \.self) { value in
                        optionChip(
                            speedLabel(Double(value)),
                            selected: abs(Double(speedState.value) - Double(value)) < 0.000_001,
                            size: 32
                        ) {
                            selectSpeed(Double(value))
                        }
                    }
                }
            }
            .id(speedStateRevision)

            if isStarting {
                ProgressView("비트맵 준비 중…")
                    .tint(AppTheme.accentPurple)
                    .frame(maxWidth: .infinity, minHeight: 34)
            } else {
                Button {
                    startGame()
                } label: {
                    Label("START", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(GradientCTAButtonStyle())
            }
        }
    }

    private func settingsPanel<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title {
                Text(title)
                    .font(.caption.weight(.bold))
            }
            content()
        }
        .padding(8)
        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.line, lineWidth: 1)
        }
    }

    private func settingCopy(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
            Text(caption)
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
    }

    private func difficultyCard(_ difficulty: Difficulty) -> some View {
        let isSelected = selectedDifficulty == difficulty

        return Button {
            selectedDifficulty = difficulty
        } label: {
            VStack(spacing: 3) {
                Image(systemName: difficulty.iconSystemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(difficulty.tint)
                    .shadow(color: difficulty.tint, radius: 10)
                Text(difficulty.displayName)
                    .font(.system(size: 9, weight: .bold))
                Text(difficulty.levelLabel)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(AppTheme.mutedBright)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? AppTheme.accentPurple.opacity(0.16) : difficulty.tint.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isSelected ? AppTheme.accentPurple : difficulty.tint.opacity(0.54),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .shadow(
            color: isSelected ? AppTheme.accentPurple.opacity(0.55) : .clear,
            radius: isSelected ? 16 : 0
        )
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }

    private func optionChip(
        _ title: String,
        selected: Bool,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? .white : AppTheme.mutedBright)
                .frame(width: size, height: size)
                .background(AppTheme.backgroundElevated, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            selected ? AppTheme.accentPurple : AppTheme.muted.opacity(0.42),
                            lineWidth: selected ? 3 : 1
                        )
                }
                .shadow(
                    color: selected ? AppTheme.accentPurple.opacity(0.45) : .clear,
                    radius: selected ? 22 : 0
                )
        }
        .buttonStyle(.plain)
    }

    private func selectSpeed(_ value: Double) {
        speedState.set(CGFloat(value))
        speedStateRevision &+= 1
        let profile = ProfileEntity.current(in: modelContext)
        profile.noteSpeedMultiplier = value
        do {
            try modelContext.save()
        } catch {
            errorMessage = "배속 설정을 저장하지 못했어요."
        }
    }

    private var trackColor: Color {
        guard let beatmapEntity = track.beatmaps.first,
              let beatmap = try? JSONDecoder().decode(
                  Beatmap.self,
                  from: beatmapEntity.beatmapData
              ) else {
            return AppTheme.accentPurple
        }
        return beatmap.palette.color
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func speedLabel(_ value: Double) -> String {
        String(format: "x%.2f", value)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
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

}
