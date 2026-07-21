import SwiftUI

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

    var tagline: String {
        switch self {
        case .heaven:
            "숨쉬듯 편안하게"
        case .easy:
            "가볍게 몸풀기"
        case .normal:
            "리듬을 타보자"
        case .hard:
            "손가락 준비운동 필수"
        case .hell:
            "건투를 빈다"
        }
    }

    var level: Int {
        switch self {
        case .heaven:
            5
        case .easy:
            10
        case .normal:
            15
        case .hard:
            20
        case .hell:
            25
        }
    }

    var levelLabel: String {
        "Lv. \(level)"
    }

    var iconSystemName: String {
        switch self {
        case .heaven:
            "star"
        case .easy:
            "star.fill"
        case .normal:
            "sparkles"
        case .hard:
            "flame.fill"
        case .hell:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .heaven:
            AppTheme.green
        case .easy:
            AppTheme.accentBlue
        case .normal:
            AppTheme.accentPurple
        case .hard:
            AppTheme.orange
        case .hell:
            AppTheme.red
        }
    }
}
