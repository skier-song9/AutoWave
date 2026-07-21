import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProfileEntity.createdAt) private var profiles: [ProfileEntity]
    @Query(sort: \ScoreRecord.playedAt, order: .reverse) private var scoreRecords: [ScoreRecord]
    @State private var isProfilePresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                primaryActions
                upcomingSection
                latestScore
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .appScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            _ = ProfileEntity.current(in: modelContext)
            try? modelContext.save()
        }
        .sheet(isPresented: $isProfilePresented) {
            if let profile = profiles.first {
                ProfileView(profile: profile)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            HomeWaveGlyph()

            Text("AutoWave")
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.accentGradient)

            Spacer()

            if let profile = profiles.first {
                Button {
                    isProfilePresented = true
                } label: {
                    ProfileChip(profile: profile)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("프로필 편집")
            }
        }
    }

    private var primaryActions: some View {
        VStack(spacing: 12) {
            NavigationLink {
                LibraryView()
            } label: {
                Label("플레이", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GradientCTAButtonStyle())

            NavigationLink {
                ImportView()
            } label: {
                Label("음원 가져오기", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GradientCTAButtonStyle(secondary: true))
        }
        .panelCard()
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("곧 만나요")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.accentPurple)

            disabledRow(title: "멀티플레이 (준비 중)", systemImage: "person.2.fill")
            disabledRow(title: "계정 연동 (준비 중)", systemImage: "link.circle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    @ViewBuilder
    private func disabledRow(title: String, systemImage: String) -> some View {
        Button {} label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(AppTheme.muted)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(AppTheme.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(true)
    }

    @ViewBuilder
    private var latestScore: some View {
        if let record = scoreRecords.first {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(AppTheme.good)
                Text(
                    "최근 기록: \(record.track.title) · \(difficultyName(for: record.difficulty)) · \(record.score)점"
                )
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelCard(padding: 12)
        }
    }

    private func difficultyName(for rawValue: String) -> String {
        Difficulty(rawValue: rawValue)?.displayName ?? rawValue
    }
}

private struct ProfileChip: View {
    let profile: ProfileEntity

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: profile.avatarSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(ProfileColor.color(for: profile.avatarTint), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.accentGradient, lineWidth: 2)
                }
                .shadow(color: AppTheme.accentPurple.opacity(0.45), radius: 10)

            Text(profile.nickname)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .background(AppTheme.backgroundElevated, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(AppTheme.accentPurple.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct HomeWaveGlyph: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(AppTheme.accentPurple.opacity(0.22), lineWidth: 1.5)
                    .scaleEffect(isAnimating ? 1.35 : 0.55)
                    .opacity(isAnimating ? 0 : 0.7)
                    .animation(
                        .easeOut(duration: 2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.55),
                        value: isAnimating
                    )
            }

            Image(systemName: "water.waves")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.accentCyan)
        }
        .frame(width: 44, height: 44)
        .onAppear { isAnimating = true }
        .accessibilityHidden(true)
    }
}
