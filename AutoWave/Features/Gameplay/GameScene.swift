import Foundation
import SpriteKit
import UIKit

@MainActor
final class GameScene: SKScene {
    private final class DropletNode: SKNode {
        let note: Note

        private let coreRadius: CGFloat = 8
        private let outerRadius: CGFloat = 34
        private let core: SKShapeNode
        private let innerRing: SKShapeNode
        private let outerRing: SKShapeNode

        var isConsumed = false

        init(note: Note, color: SKColor) {
            self.note = note
            core = SKShapeNode(circleOfRadius: 8)
            innerRing = SKShapeNode(circleOfRadius: 20)
            outerRing = SKShapeNode(circleOfRadius: 34)
            super.init()

            core.fillColor = color
            core.strokeColor = color
            core.lineWidth = 1

            innerRing.fillColor = .clear
            innerRing.strokeColor = color.withAlphaComponent(0.75)
            innerRing.lineWidth = 2

            outerRing.fillColor = .clear
            outerRing.strokeColor = color.withAlphaComponent(0.45)
            outerRing.lineWidth = 2

            addChild(outerRing)
            addChild(innerRing)
            addChild(core)
            zPosition = 3
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(
            playbackTime: TimeInterval,
            hitLineY: CGFloat,
            laneWidth: CGFloat,
            scrollSpeed: CGFloat,
            ringWindow: TimeInterval,
            sceneHeight: CGFloat
        ) {
            let timeToHit = note.time - playbackTime
            let y = hitLineY + CGFloat(timeToHit) * scrollSpeed

            guard !isConsumed, playbackTime <= note.time + 0.150 else {
                isHidden = true
                return
            }

            guard y <= sceneHeight + outerRadius, y >= -outerRadius else {
                isHidden = true
                return
            }

            isHidden = false
            position = CGPoint(
                x: (CGFloat(note.lane) + 0.5) * laneWidth,
                y: y
            )

            let progress = min(max(timeToHit / ringWindow, 0), 1)
            let radius = coreRadius + (outerRadius - coreRadius) * CGFloat(progress)
            outerRing.setScale(radius / outerRadius)
        }
    }

    private final class RibbonNode: SKNode {
        private enum State {
            case pending
            case active
            case broken
            case finished
            case inactive
        }

        private struct SpinePoint {
            let offset: TimeInterval
            let point: CGPoint
        }

        let note: Note

        private let color: SKColor
        private let band = SKShapeNode()
        private let core = SKShapeNode()
        private let completedBand = SKShapeNode()
        private let completedCore = SKShapeNode()
        private let remainingBand = SKShapeNode()
        private let remainingCore = SKShapeNode()
        private let crest = SKShapeNode(circleOfRadius: 9)

        private var state: State = .pending
        private var fingerOn = false
        private var spinePoints: [SpinePoint] = []
        private var laneWidth: CGFloat = 0
        private var scrollSpeed: CGFloat = 0
        private var breakOffset: TimeInterval?

        init(note: Note, color: SKColor) {
            self.note = note
            self.color = color
            super.init()

            band.zPosition = 0
            core.zPosition = 1
            completedBand.zPosition = 0
            completedCore.zPosition = 1
            remainingBand.zPosition = 0
            remainingCore.zPosition = 1

            crest.fillColor = color
            crest.strokeColor = color
            crest.glowWidth = 8
            crest.zPosition = 2
            crest.isHidden = true

            addChild(band)
            addChild(core)
            addChild(completedBand)
            addChild(completedCore)
            addChild(remainingBand)
            addChild(remainingCore)
            addChild(crest)
            zPosition = 1.5
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func canBegin(at time: TimeInterval, touchLane: Double) -> Bool {
            guard state == .pending else { return false }
            let timeOffset = abs(note.time - time)
            return timeOffset <= 0.150
                && abs(touchLane - lane(at: 0)) <= 0.6
        }

        func updateLayout(laneWidth: CGFloat, scrollSpeed: CGFloat) {
            self.laneWidth = laneWidth
            self.scrollSpeed = scrollSpeed
            band.lineWidth = laneWidth * 0.55
            core.lineWidth = max(laneWidth * 0.08, 1)
            completedBand.lineWidth = band.lineWidth
            completedCore.lineWidth = core.lineWidth
            remainingBand.lineWidth = band.lineWidth
            remainingCore.lineWidth = core.lineWidth
            spinePoints = makeSpinePoints()
            applyPaths()
        }

        func markActivated() {
            state = .active
            fingerOn = true
        }

        func setFingerOn(_ isOn: Bool) {
            guard state == .active else { return }
            fingerOn = isOn
        }

        func markScored(at time: TimeInterval) {
            guard state == .active else { return }
            fingerOn = true
            crest.isHidden = false
            crest.position = point(at: max(time - note.time, 0))
        }

        func markBroken(at time: TimeInterval) {
            state = .broken
            fingerOn = false
            breakOffset = min(max(time - note.time, 0), note.duration)
            applyPaths()
            crest.isHidden = true
        }

        func markFinished() {
            state = .finished
            fingerOn = false
            crest.isHidden = true
        }

        func markInactive() {
            state = .inactive
            fingerOn = false
            breakOffset = nil
            band.strokeColor = SKColor(white: 0.55, alpha: 0.25)
            core.strokeColor = SKColor(white: 0.65, alpha: 0.25)
            crest.isHidden = true
        }

        func update(
            playbackTime: TimeInterval,
            hitLineY: CGFloat,
            sceneHeight: CGFloat
        ) {
            position.y = hitLineY + CGFloat(note.time - playbackTime) * scrollSpeed

            if state == .pending, playbackTime > note.time + 0.150 {
                markInactive()
            }

            let endY = position.y - CGFloat(note.duration) * scrollSpeed
            let visible = max(position.y, endY) >= -48 && min(position.y, endY) <= sceneHeight + 48
            isHidden = !visible

            guard state == .active, fingerOn, playbackTime < note.time + note.duration else {
                crest.isHidden = true
                return
            }

            crest.isHidden = false
            crest.position = point(at: max(playbackTime - note.time, 0))
        }

        private func makeSpinePoints() -> [SpinePoint] {
            guard laneWidth > 0, scrollSpeed > 0 else { return [] }

            let steps = max(Int(ceil(note.duration / 0.1)), 1)
            return (0...steps).map { index in
                let offset = min(note.duration, Double(index) * 0.1)
                let wave = sin(Double(index) * 0.8) * Double(laneWidth * 0.04)
                let x = (CGFloat(lane(at: offset)) + 0.5) * laneWidth + CGFloat(wave)
                let y = -CGFloat(offset) * scrollSpeed
                return SpinePoint(offset: offset, point: CGPoint(x: x, y: y))
            }
        }

        private func applyPaths() {
            band.path = splinePath(from: spinePoints)
            core.path = band.path
            band.strokeColor = color.withAlphaComponent(0.45)
            core.strokeColor = color.withAlphaComponent(0.9)
            band.isHidden = false
            core.isHidden = false
            completedBand.isHidden = true
            completedCore.isHidden = true
            remainingBand.isHidden = true
            remainingCore.isHidden = true

            guard state == .broken, let breakOffset else {
                return
            }

            let boundary = SpinePoint(offset: breakOffset, point: point(at: breakOffset))
            var completed = spinePoints.filter { $0.offset < breakOffset }
            completed.append(boundary)
            var remaining = [boundary]
            remaining.append(contentsOf: spinePoints.filter { $0.offset > breakOffset })

            band.isHidden = true
            core.isHidden = true
            completedBand.path = splinePath(from: completed)
            completedCore.path = completedBand.path
            completedBand.strokeColor = color.withAlphaComponent(0.45)
            completedCore.strokeColor = color.withAlphaComponent(0.9)
            remainingBand.path = splinePath(from: remaining)
            remainingCore.path = remainingBand.path
            remainingBand.strokeColor = SKColor(white: 0.55, alpha: 0.25)
            remainingCore.strokeColor = SKColor(white: 0.65, alpha: 0.25)
            completedBand.isHidden = false
            completedCore.isHidden = false
            remainingBand.isHidden = false
            remainingCore.isHidden = false
        }

        private func splinePath(from points: [SpinePoint]) -> CGPath? {
            guard let first = points.first else { return nil }

            let path = CGMutablePath()
            path.move(to: first.point)
            guard points.count > 1 else { return path }

            var previous = first.point
            for index in 1..<points.count {
                let current = points[index].point
                let midpoint = CGPoint(
                    x: (previous.x + current.x) / 2,
                    y: (previous.y + current.y) / 2
                )
                if index == 1 {
                    path.addLine(to: midpoint)
                } else {
                    path.addQuadCurve(to: midpoint, control: previous)
                }
                previous = current
            }
            path.addLine(to: previous)
            return path
        }

        private func point(at offset: TimeInterval) -> CGPoint {
            guard let first = spinePoints.first else { return .zero }
            guard offset > first.offset else { return first.point }

            for index in 1..<spinePoints.count {
                let current = spinePoints[index]
                let previous = spinePoints[index - 1]
                guard offset <= current.offset else { continue }

                let span = current.offset - previous.offset
                guard span > 0 else { return current.point }
                let progress = (offset - previous.offset) / span
                return CGPoint(
                    x: previous.point.x + (current.point.x - previous.point.x) * CGFloat(progress),
                    y: previous.point.y + (current.point.y - previous.point.y) * CGFloat(progress)
                )
            }

            return spinePoints.last?.point ?? .zero
        }

        private func lane(at elapsed: TimeInterval) -> Double {
            var previousOffset: TimeInterval = 0
            var previousLane = note.lane

            for keyframe in note.lanePath {
                let offset = max(keyframe.offset, 0)
                guard offset > previousOffset else {
                    previousOffset = offset
                    previousLane = keyframe.lane
                    continue
                }

                guard elapsed < offset else {
                    previousOffset = offset
                    previousLane = keyframe.lane
                    continue
                }

                let progress = (elapsed - previousOffset) / (offset - previousOffset)
                return previousLane + (keyframe.lane - previousLane) * progress
            }

            return previousLane
        }
    }

    private let beatmap: Beatmap
    private let judgmentEngine: JudgmentEngine
    private let playbackTime: () -> TimeInterval
    private let playbackFinished: () -> Bool
    private let onComplete: () -> Void
    private let noteColor: SKColor
    private let scrollSpeed: CGFloat
    private let lastNoteTime: TimeInterval?

    private var noteNodes: [DropletNode] = []
    private var ribbonNodes: [RibbonNode] = []
    private var separatorNodes: [SKShapeNode] = []
    private let hitLineNode = SKShapeNode()
    private var hitLineY: CGFloat = 0
    private var hasCompleted = false
    private var activeDragTouch: UITouch?
    private var activeDragNoteID: UUID?
    private var activeDragTouchLane: Double?
    private var nextDragTickTime: TimeInterval?
    private let dragTickInterval: TimeInterval = 0.1

    init(
        beatmap: Beatmap,
        difficulty: Difficulty,
        judgmentEngine: JudgmentEngine,
        playbackTime: @escaping () -> TimeInterval,
        playbackFinished: @escaping () -> Bool,
        onComplete: @escaping () -> Void
    ) {
        self.beatmap = beatmap
        self.judgmentEngine = judgmentEngine
        self.playbackTime = playbackTime
        self.playbackFinished = playbackFinished
        self.onComplete = onComplete
        noteColor = SKColor(
            hue: beatmap.palette.hue,
            saturation: min(max(beatmap.palette.saturation, 0), 1),
            brightness: min(max(beatmap.palette.brightness, 0), 1),
            alpha: 1
        )
        scrollSpeed = CGFloat(DifficultyProfile.profile(for: difficulty).scrollSpeed)
        lastNoteTime = beatmap.notes.map(\.time).max()
        super.init(size: UIScreen.main.bounds.size)
        scaleMode = .resizeFill
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(
            hue: beatmap.palette.hue,
            saturation: min(max(beatmap.palette.saturation, 0), 1),
            brightness: min(max(beatmap.palette.brightness * 0.35, 0), 1),
            alpha: 1
        )

        addChild(hitLineNode)
        hitLineNode.zPosition = 2
        hitLineNode.strokeColor = noteColor.withAlphaComponent(0.7)
        hitLineNode.lineWidth = 2

        for note in beatmap.notes where note.kind == .tap {
            let node = DropletNode(note: note, color: noteColor)
            noteNodes.append(node)
            addChild(node)
        }

        for note in beatmap.notes where note.kind == .drag {
            let node = RibbonNode(note: note, color: noteColor)
            ribbonNodes.append(node)
            addChild(node)
        }

        updateLayout()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateLayout()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !hasCompleted else { return }

        let time = playbackTime()
        let misses = judgmentEngine.advance(to: time)
        for miss in misses {
            showJudgment(miss)
        }

        advanceDragTicks(to: time)

        let ringWindow = max(
            TimeInterval(max(size.height - hitLineY, 0)) / TimeInterval(scrollSpeed),
            0.1
        )
        let laneWidth = size.width / 4
        for node in noteNodes {
            node.update(
                playbackTime: time,
                hitLineY: hitLineY,
                laneWidth: laneWidth,
                scrollSpeed: scrollSpeed,
                ringWindow: ringWindow,
                sceneHeight: size.height
            )
        }
        for node in ribbonNodes {
            node.update(
                playbackTime: time,
                hitLineY: hitLineY,
                sceneHeight: size.height
            )
        }

        if playbackFinished() || (lastNoteTime.map { time >= $0 + 2 } ?? false) {
            hasCompleted = true
            onComplete()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, size.width > 0 else { return }

        let location = touch.location(in: self)
        let touchLane = laneCoordinate(for: location)
        let time = playbackTime()

        if activeDragNoteID == nil,
           let ribbon = nearestRibbon(at: time, touchLane: touchLane),
           let result = judgmentEngine.beginDrag(
               noteID: ribbon.note.id,
               touchLane: touchLane,
               at: time
           ) {
            ribbon.markActivated()
            activeDragTouch = touch
            activeDragNoteID = ribbon.note.id
            activeDragTouchLane = touchLane
            showJudgment(result)
            return
        }

        let lane = min(max(Int(location.x / (size.width / 4)), 0), 3)

        guard let result = judgmentEngine.tap(lane: lane, at: time) else { return }

        consumeNearestVisual(lane: lane, at: time)
        showJudgment(result)
        if result.judgment != .miss {
            showSplash(at: CGPoint(x: (CGFloat(lane) + 0.5) * size.width / 4, y: hitLineY))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeDragTouch, touches.contains(where: { $0 === activeDragTouch }) else {
            return
        }

        let location = activeDragTouch.location(in: self)
        activeDragTouchLane = laneCoordinate(for: location)
        if let activeDragNoteID, let ribbon = ribbonNode(for: activeDragNoteID) {
            ribbon.setFingerOn(true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateEndedDragTouch(in: touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateEndedDragTouch(in: touches)
    }

    private func updateLayout() {
        guard size.width > 0, size.height > 0 else { return }

        hitLineY = size.height * 0.15
        let hitLinePath = CGMutablePath()
        hitLinePath.move(to: CGPoint(x: 0, y: hitLineY))
        hitLinePath.addLine(to: CGPoint(x: size.width, y: hitLineY))
        hitLineNode.path = hitLinePath

        if separatorNodes.isEmpty {
            for _ in 1..<4 {
                let separator = SKShapeNode()
                separator.strokeColor = noteColor.withAlphaComponent(0.14)
                separator.lineWidth = 1
                separator.zPosition = 1
                separatorNodes.append(separator)
                addChild(separator)
            }
        }

        for (index, separator) in separatorNodes.enumerated() {
            separator.path = wavePath(x: size.width * CGFloat(index + 1) / 4)
        }

        let laneWidth = size.width / 4
        for node in ribbonNodes {
            node.updateLayout(laneWidth: laneWidth, scrollSpeed: scrollSpeed)
        }
    }

    private func advanceDragTicks(to time: TimeInterval) {
        if nextDragTickTime == nil {
            nextDragTickTime = (floor(time / dragTickInterval) + 1) * dragTickInterval
        }

        while let tickTime = nextDragTickTime, tickTime <= time + 0.000_000_001 {
            processDragTick(at: tickTime)
            nextDragTickTime = tickTime + dragTickInterval
        }
    }

    private func processDragTick(at time: TimeInterval) {
        guard let noteID = activeDragNoteID else { return }

        let result = judgmentEngine.dragTick(
            noteID: noteID,
            touchLane: activeDragTouchLane,
            at: time
        )
        guard let ribbon = ribbonNode(for: noteID) else {
            clearActiveDrag()
            return
        }

        switch result {
        case .scored:
            ribbon.markScored(at: time)
        case .broken:
            ribbon.markBroken(at: time)
            clearActiveDrag()
        case .finished:
            ribbon.markFinished()
            clearActiveDrag()
        case .inactive:
            ribbon.markInactive()
            clearActiveDrag()
        }
    }

    private func nearestRibbon(at time: TimeInterval, touchLane: Double) -> RibbonNode? {
        var nearest: RibbonNode?
        var nearestDistance = TimeInterval(0.150).nextUp

        for node in ribbonNodes where node.canBegin(at: time, touchLane: touchLane) {
            let distance = abs(node.note.time - time)
            guard distance < nearestDistance else { continue }
            nearest = node
            nearestDistance = distance
        }

        return nearest
    }

    private func ribbonNode(for noteID: UUID) -> RibbonNode? {
        ribbonNodes.first { $0.note.id == noteID }
    }

    private func laneCoordinate(for point: CGPoint) -> Double {
        Double(point.x / (size.width / 4) - 0.5)
    }

    private func updateEndedDragTouch(in touches: Set<UITouch>) {
        guard let activeDragTouch, touches.contains(where: { $0 === activeDragTouch }) else {
            return
        }

        activeDragTouchLane = nil
        if let activeDragNoteID, let ribbon = ribbonNode(for: activeDragNoteID) {
            ribbon.setFingerOn(false)
        }
    }

    private func clearActiveDrag() {
        activeDragTouch = nil
        activeDragNoteID = nil
        activeDragTouchLane = nil
    }

    private func wavePath(x: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let step: CGFloat = 18
        path.move(to: CGPoint(x: x, y: 0))

        var y: CGFloat = 0
        while y <= size.height {
            let offset = sin(Double(y / 42)) * 3
            path.addLine(to: CGPoint(x: x + offset, y: y))
            y += step
        }

        return path
    }

    private func consumeNearestVisual(lane: Int, at time: TimeInterval) {
        var nearest: DropletNode?
        var nearestDistance = TimeInterval(0.150).nextUp

        for node in noteNodes where !node.isConsumed && node.note.lane == Double(lane) {
            let distance = abs(node.note.time - time)
            guard distance <= 0.150, distance < nearestDistance else { continue }
            nearest = node
            nearestDistance = distance
        }

        nearest?.isConsumed = true
        nearest?.isHidden = true
    }

    private func showJudgment(_ result: JudgmentResult) {
        let judgmentText: String
        switch result.judgment {
        case .perfect:
            judgmentText = "PERFECT"
        case .great:
            judgmentText = "GREAT"
        case .good:
            judgmentText = "GOOD"
        case .miss:
            judgmentText = "MISS"
        }

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = "\(judgmentText) · COMBO \(result.combo)"
        label.fontSize = 24
        label.fontColor = noteColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.zPosition = 10
        label.alpha = 0
        addChild(label)

        let show = SKAction.fadeIn(withDuration: 0.05)
        let hide = SKAction.sequence([
            .wait(forDuration: 0.45),
            .fadeOut(withDuration: 0.25),
            .removeFromParent()
        ])
        label.run(.sequence([show, hide]))
    }

    private func showSplash(at point: CGPoint) {
        let ripple = SKShapeNode(circleOfRadius: 10)
        ripple.position = point
        ripple.strokeColor = noteColor
        ripple.fillColor = .clear
        ripple.lineWidth = 2
        ripple.zPosition = 8
        addChild(ripple)
        ripple.run(.sequence([
            .group([
                .scale(to: 3.5, duration: 0.3),
                .fadeOut(withDuration: 0.3)
            ]),
            .removeFromParent()
        ]))

        for index in 0..<8 {
            let particle = SKShapeNode(circleOfRadius: 2)
            particle.position = point
            particle.fillColor = noteColor
            particle.strokeColor = .clear
            particle.zPosition = 8
            addChild(particle)

            let angle = Double(index) * .pi / 4
            let distance: CGFloat = 34
            let destination = CGVector(
                dx: cos(angle) * Double(distance),
                dy: sin(angle) * Double(distance)
            )
            particle.run(.sequence([
                .group([
                    .move(by: destination, duration: 0.32),
                    .fadeOut(withDuration: 0.32)
                ]),
                .removeFromParent()
            ]))
        }
    }
}
