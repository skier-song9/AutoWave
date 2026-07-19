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
    var sourceRole: MusicalRole? = nil

    init(
        id: UUID,
        kind: NoteKind,
        time: TimeInterval,
        lane: Double,
        duration: TimeInterval,
        lanePath: [LaneKeyframe],
        sourceRole: MusicalRole? = nil
    ) {
        self.id = id
        self.kind = kind
        self.time = time
        self.lane = lane
        self.duration = duration
        self.lanePath = lanePath
        self.sourceRole = sourceRole
    }
}
