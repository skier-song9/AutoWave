import SwiftUI

struct ResultsView: View {
    let summary: GameplaySummary
    let trackTitle: String
    let difficulty: Difficulty
    let onRestart: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.accentPurple.opacity(0.22), lineWidth: 1)
                .frame(width: 310, height: 310)
            Circle()
                .stroke(AppTheme.accentBlue.opacity(0.035), lineWidth: 64)
                .frame(width: 310, height: 310)

            VStack(spacing: 24) {
                Text("플레이 결과")
                    .font(.largeTitle.bold())

                VStack(spacing: 8) {
                    Text(trackTitle)
                        .font(.title3)
                    Text(difficulty.displayName)
                        .foregroundStyle(AppTheme.mutedBright)
                }

                Text("\(summary.score)")
                    .font(.system(size: 64, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AppTheme.accentGradient)

                HStack(spacing: 20) {
                    resultValue(title: "최대 콤보", value: "\(summary.maxCombo)", color: AppTheme.accentPurple)
                    resultValue(title: "퍼펙트", value: "\(summary.judgmentCounts.perfect)", color: AppTheme.accentCyan)
                    resultValue(title: "그레이트", value: "\(summary.judgmentCounts.great)", color: AppTheme.green)
                    resultValue(title: "굿", value: "\(summary.judgmentCounts.good)", color: Color(hex: 0xFDE047))
                    resultValue(title: "미스", value: "\(summary.judgmentCounts.miss)", color: AppTheme.red)
                }

                HStack(spacing: 16) {
                    Button("다시하기", action: onRestart)
                        .buttonStyle(GradientCTAButtonStyle())
                    Button("곡 선택", action: onLibrary)
                        .buttonStyle(GradientCTAButtonStyle(secondary: true))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(AppTheme.background.ignoresSafeArea())
        .foregroundStyle(AppTheme.text)
    }

    private func resultValue(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .shadow(color: color, radius: 12)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
    }
}
