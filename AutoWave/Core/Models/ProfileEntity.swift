import Foundation
import SwiftData

@Model
final class ProfileEntity {
    var nickname: String
    var avatarSymbol: String
    var avatarTint: String
    var createdAt: Date
    var noteSpeedMultiplier: Double = 1.0
    var preferredLaneCount: Int? = nil

    init(
        nickname: String = "플레이어",
        avatarSymbol: String = "water.waves",
        avatarTint: String = "#4FC3F7",
        createdAt: Date = Date(),
        noteSpeedMultiplier: Double = 1.0,
        preferredLaneCount: Int? = nil
    ) {
        self.nickname = nickname
        self.avatarSymbol = avatarSymbol
        self.avatarTint = avatarTint
        self.createdAt = createdAt
        self.noteSpeedMultiplier = noteSpeedMultiplier
        self.preferredLaneCount = preferredLaneCount
    }

    static func current(in context: ModelContext) -> ProfileEntity {
        let profiles = (try? context.fetch(FetchDescriptor<ProfileEntity>())) ?? []
        if let profile = profiles.first {
            return profile
        }

        let profile = ProfileEntity()
        context.insert(profile)
        return profile
    }

    static func validatedNickname(_ input: String) -> String? {
        let nickname = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty, nickname.count <= 12 else { return nil }
        return nickname
    }
}
