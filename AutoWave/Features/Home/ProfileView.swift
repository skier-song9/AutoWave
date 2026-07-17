import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let profile: ProfileEntity

    @State private var nickname: String
    @State private var lastValidNickname: String
    @State private var errorMessage: String?

    private let avatarSymbols = [
        "water.waves",
        "bolt.fill",
        "music.note",
        "flame.fill",
        "star.fill",
        "moon.stars.fill",
        "pawprint.fill",
        "gamecontroller.fill"
    ]

    private let tintHexes = [
        "#4FC3F7",
        "#FF4081",
        "#26C6DA",
        "#FFCA7A",
        "#B39DDB",
        "#80DEEA"
    ]

    init(profile: ProfileEntity) {
        self.profile = profile
        _nickname = State(initialValue: profile.nickname)
        _lastValidNickname = State(initialValue: profile.nickname)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("닉네임") {
                    TextField("닉네임", text: $nickname)
                        .onChange(of: nickname, initial: false) { _, newValue in
                            updateNickname(newValue)
                        }

                    Text("\(nickname.count)/12")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Section("아바타") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHGrid(
                            rows: [GridItem(.fixed(48)), GridItem(.fixed(48))],
                            spacing: 12
                        ) {
                            ForEach(avatarSymbols, id: \.self) { symbol in
                                Button {
                                    profile.avatarSymbol = symbol
                                    saveProfile()
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.title3)
                                        .foregroundStyle(
                                            profile.avatarSymbol == symbol ? .white : .primary
                                        )
                                        .frame(width: 48, height: 48)
                                        .background(
                                            profile.avatarSymbol == symbol
                                                ? ProfileColor.color(for: profile.avatarTint)
                                                : Color.secondary.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    profile.avatarSymbol == symbol ? "선택한 아바타" : "아바타 선택"
                                )
                            }
                        }
                        .frame(height: 108)
                        .padding(.vertical, 4)
                    }
                }

                Section("색상") {
                    HStack(spacing: 16) {
                        ForEach(tintHexes, id: \.self) { hex in
                            Button {
                                profile.avatarTint = hex
                                saveProfile()
                            } label: {
                                Circle()
                                    .fill(ProfileColor.color(for: hex))
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                .primary,
                                                lineWidth: profile.avatarTint == hex ? 3 : 0
                                            )
                                            .padding(2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                profile.avatarTint == hex ? "선택한 색상" : "색상 선택"
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .navigationTitle("프로필")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
            .alert("저장 오류", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "프로필을 저장하지 못했어요.")
            }
        }
    }

    private func updateNickname(_ newValue: String) {
        guard let validated = ProfileEntity.validatedNickname(newValue) else {
            nickname = lastValidNickname
            return
        }

        if nickname != validated {
            nickname = validated
        }
        lastValidNickname = validated
        guard profile.nickname != validated else { return }

        profile.nickname = validated
        saveProfile()
    }

    private func saveProfile() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = "프로필을 저장하지 못했어요."
        }
    }
}

enum ProfileColor {
    static func color(for hex: String) -> Color {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else {
            return .accentColor
        }

        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
