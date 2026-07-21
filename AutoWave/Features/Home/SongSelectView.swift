import Foundation
import SwiftData
import SwiftUI

struct SongSelectView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrackEntity.importedAt, order: .reverse) private var tracks: [TrackEntity]
    @Query(sort: \ProfileEntity.createdAt) private var profiles: [ProfileEntity]

    @State private var focusedIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isImportPresented = false
    @State private var isProfilePresented = false
    @State private var readyTrack: TrackEntity?
    @State private var gameplayTrack: TrackEntity?
    @State private var gameplayDifficulty: Difficulty?
    @State private var noteSpeedState = NoteSpeedMultiplierState()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SpaceBackdrop()

                if tracks.isEmpty {
                    emptyState
                } else {
                    carousel(in: proxy.size)
                }

                controls
            }
        }
        .appScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            _ = ProfileEntity.current(in: modelContext)
            try? modelContext.save()
        }
        .onChange(of: tracks.count) { _, count in
            focusedIndex = min(focusedIndex, max(count - 1, 0))
        }
        .sheet(isPresented: $isProfilePresented) {
            if let profile = profiles.first {
                ProfileView(profile: profile)
            }
        }
        .navigationDestination(isPresented: $isImportPresented) {
            ImportView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { readyTrack != nil },
            set: { if !$0 { readyTrack = nil } }
        )) {
            if let readyTrack {
                ReadyModal(
                    track: readyTrack,
                    difficulty: .normal,
                    speedState: noteSpeedState
                ) { difficulty in
                    gameplayTrack = readyTrack
                    gameplayDifficulty = difficulty
                }
                .presentationBackground(.clear)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { gameplayTrack != nil && gameplayDifficulty != nil },
            set: {
                if !$0 {
                    gameplayTrack = nil
                    gameplayDifficulty = nil
                }
            }
        )) {
            if let gameplayTrack, let gameplayDifficulty {
                GameplayContainerView(
                    track: gameplayTrack,
                    difficulty: gameplayDifficulty,
                    noteSpeedState: noteSpeedState
                )
            }
        }
    }

    private var controls: some View {
        VStack {
            HStack(alignment: .top) {
                if let profile = profiles.first {
                    Button {
                        isProfilePresented = true
                    } label: {
                        PlayerBadge(profile: profile)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("프로필 편집")
                }

                Spacer()

                CircleIconButton(systemName: "plus", compact: true) {
                    isImportPresented = true
                }
                .accessibilityLabel("음원 가져오기")
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    private var emptyState: some View {
        Button {
            isImportPresented = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.accentGradient)
                    .shadow(color: AppTheme.accentPurple.opacity(0.45), radius: 14)

                Text("음원 파일 선택")
                    .font(.headline.weight(.bold))

                Text("mp3 · m4a · wav")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(width: 280, height: 150)
            .background(
                LinearGradient(
                    colors: [AppTheme.panel, AppTheme.backgroundElevated],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        AppTheme.accentGradient,
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                    )
            }
            .shadow(color: AppTheme.accentPurple.opacity(0.45), radius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityHint("음원 가져오기 화면 열기")
    }

    private func carousel(in size: CGSize) -> some View {
        let focusedDiameter = min(214, size.height * 0.56)
        let neighborDiameter = focusedDiameter * 0.565
        let step = max(neighborDiameter * 0.72, 78)

        return ZStack {
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                let distance = index - focusedIndex
                if abs(distance) <= 2 {
                    Button {
                        if distance == 0 {
                            readyTrack = track
                        } else {
                            moveFocus(to: index)
                        }
                    } label: {
                        AlbumDisc(
                            track: track,
                            diameter: distance == 0 ? focusedDiameter : neighborDiameter,
                            focused: distance == 0,
                            page: focusedIndex
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(distance == 0 ? 1 : 0.56)
                    .offset(y: CGFloat(distance) * step + dragOffset)
                    .zIndex(Double(10 - abs(distance)))
                }
            }

            HStack {
                carouselArrow(systemName: "chevron.left", label: "이전 곡") {
                    moveFocus(by: -1)
                }

                Spacer()

                carouselArrow(systemName: "chevron.right", label: "다음 곡") {
                    moveFocus(by: 1)
                }
            }
            .padding(.horizontal, max(size.width * 0.31, 110))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let threshold = max(step * 0.38, 42)
                    if value.translation.height < -threshold {
                        moveFocus(by: 1)
                    } else if value.translation.height > threshold {
                        moveFocus(by: -1)
                    } else {
                        withAnimation(.easeOut(duration: 0.16)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    private func carouselArrow(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(AppTheme.text)
                .frame(width: 44, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shadow(color: AppTheme.text.opacity(0.7), radius: 8)
        .accessibilityLabel(label)
    }

    private func moveFocus(by offset: Int) {
        moveFocus(to: focusedIndex + offset)
    }

    private func moveFocus(to index: Int) {
        let target = min(max(index, 0), tracks.count - 1)
        guard target != focusedIndex else {
            withAnimation(.easeOut(duration: 0.16)) {
                dragOffset = 0
            }
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            focusedIndex = target
            dragOffset = 0
        }
    }
}

private struct SpaceBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array([0.40, 0.63, 0.86, 1.13].enumerated()), id: \.offset) { index, scale in
                    Circle()
                        .stroke(
                            index.isMultiple(of: 2)
                                ? AppTheme.accentBlue.opacity(0.18)
                                : AppTheme.accentPurple.opacity(0.14),
                            lineWidth: 1
                        )
                        .frame(
                            width: proxy.size.width * CGFloat(scale),
                            height: proxy.size.width * CGFloat(scale)
                        )
                }

                HStack {
                    WaveformTicks()
                    Spacer()
                    WaveformTicks()
                }
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

private struct WaveformTicks: View {
    private let widths: [CGFloat] = [0.28, 0.46, 0.72, 0.38, 0.88, 0.54, 0.34, 0.65, 0.44, 0.76, 0.30, 0.58, 0.42]

    var body: some View {
        VStack(spacing: 7) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                Rectangle()
                    .fill(AppTheme.accentBlue.opacity(index.isMultiple(of: 3) ? 0.30 : 0.18))
                    .frame(width: 92 * width, height: 1)
            }
        }
        .frame(width: 96, alignment: .leading)
        .mask {
            LinearGradient(
                colors: [.clear, .black, .black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

private struct PlayerBadge: View {
    let profile: ProfileEntity

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: profile.avatarSymbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(ProfileColor.color(for: profile.avatarTint), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.accentGradient, lineWidth: 2)
                }
                .shadow(color: AppTheme.accentPurple.opacity(0.45), radius: 12)

            Text(profile.nickname.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(AppTheme.backgroundElevated, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(AppTheme.accentPurple.opacity(0.72), lineWidth: 1)
                }
        }
    }
}

private struct AlbumDisc: View {
    let track: TrackEntity
    let diameter: CGFloat
    let focused: Bool
    let page: Int

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [trackColor, AppTheme.accentPurple, AppTheme.background],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    if focused {
                        Circle()
                            .strokeBorder(AppTheme.accentGradient, lineWidth: 3)
                    } else {
                        Circle()
                            .strokeBorder(AppTheme.text.opacity(0.76), lineWidth: 1)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(AppTheme.text.opacity(0.16), lineWidth: 1)
                        .padding(diameter * 0.07)
                }
                .shadow(
                    color: focused ? AppTheme.accentPurple.opacity(0.75) : .black.opacity(0.24),
                    radius: focused ? 26 : 10
                )

            LinearGradient(
                colors: [.clear, AppTheme.background.opacity(focused ? 0.86 : 0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(Circle())

            VStack(spacing: focused ? 4 : 2) {
                Text(track.title)
                    .font(.system(size: focused ? 17 : 10, weight: .bold))
                    .lineLimit(1)

                Text("로컬 음원 · \(formattedDuration(track.duration))")
                    .font(.system(size: focused ? 11 : 8, design: .rounded))
                    .foregroundStyle(AppTheme.mutedBright)
                    .lineLimit(1)

                if focused {
                    if let difficulty = highestDifficulty {
                        HStack(spacing: 5) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(difficulty.rawValue.uppercased())
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        }
                        .foregroundStyle(difficulty.tint)
                    }

                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { index in
                            Circle()
                                .fill(index == page % 5 ? .white : AppTheme.muted)
                                .frame(width: 4, height: 4)
                                .shadow(color: index == page % 5 ? .white : .clear, radius: 5)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, focused ? 12 : 7)
            .padding(.bottom, focused ? 18 : 13)
            .shadow(color: AppTheme.background, radius: 7)
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topLeading) {
            if focused {
                ForEach(Array([(CGFloat(0.20), CGFloat(0.10)), (CGFloat(0.84), CGFloat(0.24)), (CGFloat(0.74), CGFloat(0.83)), (CGFloat(0.08), CGFloat(0.66))].enumerated()), id: \.offset) { _, point in
                    Sparkle()
                        .position(x: diameter * point.0, y: diameter * point.1)
                }
            }
        }
        .clipped()
    }

    private var trackColor: Color {
        guard let beatmap = track.beatmaps.compactMap({
            try? JSONDecoder().decode(Beatmap.self, from: $0.beatmapData)
        }).first else {
            return AppTheme.accentPurple
        }
        return beatmap.palette.color
    }

    private var highestDifficulty: Difficulty? {
        Difficulty.allCases.last { difficulty in
            track.beatmaps.contains { $0.difficulty == difficulty.rawValue }
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct Sparkle: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.24))
            .frame(width: 8, height: 8)
            .overlay {
                Rectangle()
                    .stroke(.white, lineWidth: 1)
            }
            .rotationEffect(.degrees(45))
            .shadow(color: .white, radius: 5)
    }
}
