import Foundation

enum NoteKind: String, Codable, Sendable, Equatable {
    case tap, drag
}

struct LaneKeyframe: Codable, Sendable, Equatable {
    var offset: TimeInterval
    var lane: Double
}

struct Note: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var kind: NoteKind
    var time: TimeInterval
    var lane: Double
    var duration: TimeInterval
    var lanePath: [LaneKeyframe]
}
