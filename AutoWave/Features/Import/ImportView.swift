import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var importedTrack: TrackEntity?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            if isImporting {
                ProgressView("음원 가져오는 중…")
                    .tint(AppTheme.accentPurple)
            } else if let importedTrack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.green)
                Text("가져오기 완료")
                    .font(.headline)
                Text(importedTrack.title)
                    .foregroundStyle(AppTheme.muted)
                Button("라이브러리로 돌아가기") {
                    dismiss()
                }
                .buttonStyle(GradientCTAButtonStyle())
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(AppTheme.accentGradient)
                    Text("음원 파일 선택")
                        .font(.headline)
                    Text("mp3 · m4a · wav")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                    Button("파일 열기") {
                        isImporterPresented = true
                    }
                    .buttonStyle(GradientCTAButtonStyle())
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .padding(.horizontal, 30)
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
        }
        .padding()
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appScreenBackground()
        .navigationTitle("음원 가져오기")
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                errorMessage = "파일을 선택하지 못했어요. 다시 시도해 주세요."
                return
            }

            isImporting = true
            errorMessage = nil
            Task { @MainActor in
                do {
                    importedTrack = try await AudioImportService.importAudio(from: url, into: modelContext)
                } catch {
                    errorMessage = "음원을 가져오지 못했어요. 파일을 다시 선택해 주세요."
                }
                isImporting = false
            }
        }
        .alert("가져오기 오류", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "알 수 없는 오류")
        }
    }
}
