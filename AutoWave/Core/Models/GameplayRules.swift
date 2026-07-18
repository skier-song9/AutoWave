import CoreGraphics
import Foundation

enum GameplayLayout {
    static let laneWidthRatio: CGFloat = 0.70

    static func laneAreaRect(in size: CGSize) -> CGRect {
        let width = size.width * laneWidthRatio
        return CGRect(
            x: (size.width - width) / 2,
            y: 0,
            width: width,
            height: size.height
        )
    }

    static func laneCoordinate(
        for point: CGPoint,
        in laneAreaRect: CGRect,
        laneWidth: CGFloat
    ) -> Double? {
        guard laneWidth > 0 else { return nil }

        let tolerance = laneWidth * 0.5
        guard point.x >= laneAreaRect.minX - tolerance,
              point.x <= laneAreaRect.maxX + tolerance else {
            return nil
        }

        let x = min(max(point.x, laneAreaRect.minX), laneAreaRect.maxX)
        return Double((x - laneAreaRect.minX) / laneWidth - 0.5)
    }

    static func hitLineY(in size: CGSize) -> CGFloat {
        max(size.height * 0.18, 72)
    }

    static func ribbonPositions(
        hitLineY: CGFloat,
        timeToHit: TimeInterval,
        duration: TimeInterval,
        scrollSpeed: CGFloat
    ) -> (head: CGFloat, tail: CGFloat) {
        let head = hitLineY + CGFloat(timeToHit) * scrollSpeed
        return (head, head + CGFloat(duration) * scrollSpeed)
    }
}

enum GameplayBeatmapSanitizer {
    static func removeTapConflicts(from notes: [Note]) -> [Note] {
        let drags = notes.filter { $0.kind == .drag }
        return notes.filter { note in
            note.kind == .drag || !tapConflictsWithDrag(note, drags: drags)
        }
    }

    private static func tapConflictsWithDrag(_ tap: Note, drags: [Note]) -> Bool {
        drags.contains { drag in
            let dragLanes = [drag.lane] + drag.lanePath.map(\.lane)
            let minimumLane = dragLanes.min() ?? drag.lane
            let maximumLane = dragLanes.max() ?? drag.lane
            let isActive = tap.time >= drag.time - 1e-9
                && tap.time <= drag.time + drag.duration + 1e-9
            return isActive && tap.lane >= minimumLane && tap.lane <= maximumLane
        }
    }
}
