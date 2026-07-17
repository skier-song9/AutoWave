import Foundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrackEntity.importedAt, order: .reverse) private var tracks: [TrackEntity]
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "라이브러리가 비어 있어요",
                    systemImage: "waveform",
                    description: Text("음원을 가져오면 여기에 표시됩니다.")
                )
            } else {
                List {
                    ForEach(tracks) { track in
                        NavigationLink {
                            destination(for: track)
                        } label: {
                            TrackRow(track: track)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(track)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("라이브러리")
        .alert("삭제 오류", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "알 수 없는 오류")
        }
    }

    @ViewBuilder
    private func destination(for track: TrackEntity) -> some View {
        if track.beatmaps.isEmpty {
            AnalysisView(track: track)
        } else {
            DifficultyPickerView(track: track)
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

private struct DifficultyPickerView: View {
    let track: TrackEntity

    var body: some View {
        List {
            ForEach(Difficulty.allCases, id: \.rawValue) { difficulty in
                if track.beatmaps.contains(where: { $0.difficulty == difficulty.rawValue }) {
                    NavigationLink {
                        GameplayContainerView(track: track, difficulty: difficulty)
                    } label: {
                        Text(difficulty.displayName)
                    }
                } else {
                    Button {
                    } label: {
                        HStack {
                            Text(difficulty.displayName)
                            Spacer()
                            Text("준비 중")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(true)
                }
            }
        }
        .navigationTitle("난이도 선택")
    }
}
