import SwiftUI

@MainActor
struct AnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: AnalysisViewModel

    private let track: TrackEntity?

    init() {
        track = nil
        _viewModel = State(initialValue: AnalysisViewModel())
    }

    init(track: TrackEntity) {
        self.track = track
        _viewModel = State(initialValue: AnalysisViewModel())
    }

    var body: some View {
        Group {
            if let track {
                content(for: track)
            } else {
                Text("변환할 음원을 선택해 주세요.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("변환")
        .task(id: track?.persistentModelID) {
            guard let track else { return }
            await viewModel.start(track: track, context: modelContext)
        }
    }

    @ViewBuilder
    private func content(for track: TrackEntity) -> some View {
        switch viewModel.state {
        case .idle:
            progressContent(title: "분석 중…", detail: "0%", progress: 0)
        case .analyzing(let progress):
            progressContent(
                title: "분석 중…",
                detail: "\(percentage(progress))%",
                progress: progress
            )
        case .generating(let current, let total):
            progressContent(
                title: "비트맵 생성 중…",
                detail: "(\(current)/\(total))",
                progress: Double(current) / Double(total)
            )
        case .done:
            VStack(spacing: 24) {
                Text("완료!")
                    .font(.largeTitle.bold())
                Text(track.title)
                    .foregroundStyle(.secondary)
                Button("라이브러리로") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        case .failed(let message):
            VStack(spacing: 20) {
                Text(message)
                    .font(.headline)
                Button("다시 시도") {
                    Task { @MainActor in
                        await viewModel.start(track: track, context: modelContext)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private func progressContent(title: String, detail: String, progress: Double) -> some View {
        VStack(spacing: 24) {
            RippleProgressView(progress: progress)
                .frame(width: 180, height: 180)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func percentage(_ progress: Double) -> Int {
        Int((min(max(progress, 0), 1) * 100).rounded())
    }
}

private struct RippleProgressView: View {
    let progress: Double
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(.tint.opacity(0.25 + Double(2 - index) * 0.1), lineWidth: 2)
                    .scaleEffect(isAnimating ? 1.2 : 0.35)
                    .opacity(isAnimating ? 0 : 0.9)
                    .animation(
                        .easeOut(duration: 2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.55),
                        value: isAnimating
                    )
            }

            Circle()
                .fill(.tint.opacity(0.12))
                .overlay {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(28)
        }
        .onAppear { isAnimating = true }
        .accessibilityValue("\(Int(progress * 100))%")
    }
}
