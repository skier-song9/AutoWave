import CoreGraphics
import Foundation

struct PerspectiveProjection: Equatable, Sendable {
    static let defaultTopScale: CGFloat = 0.22

    let centerX: CGFloat
    let topY: CGFloat
    let hitLineY: CGFloat
    let bottomLaneWidth: CGFloat
    let laneCount: Int
    let topScale: CGFloat

    init(
        centerX: CGFloat,
        topY: CGFloat,
        hitLineY: CGFloat,
        bottomLaneWidth: CGFloat,
        laneCount: Int,
        topScale: CGFloat = PerspectiveProjection.defaultTopScale
    ) {
        self.centerX = centerX
        self.topY = topY
        self.hitLineY = hitLineY
        self.bottomLaneWidth = bottomLaneWidth
        self.laneCount = laneCount
        self.topScale = topScale
    }

    var travelHeight: CGFloat {
        max(topY - hitLineY, 0)
    }

    func progress(timeToHit: TimeInterval, scrollSpeed: CGFloat) -> CGFloat {
        guard travelHeight > 0 else { return 1 }
        return 1 - CGFloat(timeToHit) * scrollSpeed / travelHeight
    }

    func y(at progress: CGFloat) -> CGFloat {
        topY - travelHeight * progress
    }

    func laneWidth(at progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return bottomLaneWidth * (topScale + (1 - topScale) * clampedProgress)
    }

    func laneCenterX(_ lane: Double, at progress: CGFloat) -> CGFloat {
        centerX + (CGFloat(lane) + 0.5 - CGFloat(laneCount) / 2) * laneWidth(at: progress)
    }

    func laneBoundaryX(_ boundary: Int, at progress: CGFloat) -> CGFloat {
        centerX + (CGFloat(boundary) - CGFloat(laneCount) / 2) * laneWidth(at: progress)
    }

    func scale(at progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return topScale + (1 - topScale) * clampedProgress
    }

    func point(lane: Double, at progress: CGFloat) -> CGPoint {
        CGPoint(x: laneCenterX(lane, at: progress), y: y(at: progress))
    }
}

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
