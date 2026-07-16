enum Difficulty: String, Codable, CaseIterable, Sendable, Equatable {
    case heaven, easy, normal, hard, hell

    var displayName: String {
        switch self {
        case .heaven:
            "천국"
        case .easy:
            "쉬움"
        case .normal:
            "보통"
        case .hard:
            "어려움"
        case .hell:
            "지옥"
        }
    }
}
