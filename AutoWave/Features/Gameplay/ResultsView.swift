import SwiftUI

struct ResultsView: View {
    let summary: GameplaySummary
    let trackTitle: String
    let difficulty: Difficulty
    let onRestart: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("플레이 결과")
                .font(.largeTitle.bold())

            VStack(spacing: 8) {
                Text(trackTitle)
                    .font(.title3)
                Text(difficulty.displayName)
                    .foregroundStyle(.secondary)
            }

            Text("\(summary.score)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 36) {
                resultValue(title: "최대 콤보", value: "\(summary.maxCombo)")
                resultValue(title: "퍼펙트", value: "\(summary.judgmentCounts.perfect)")
                resultValue(title: "그레이트", value: "\(summary.judgmentCounts.great)")
                resultValue(title: "굿", value: "\(summary.judgmentCounts.good)")
                resultValue(title: "미스", value: "\(summary.judgmentCounts.miss)")
            }

            HStack(spacing: 16) {
                Button("다시하기", action: onRestart)
                    .buttonStyle(.borderedProminent)
                Button("라이브러리", action: onLibrary)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(.black)
        .foregroundStyle(.white)
    }

    private func resultValue(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
