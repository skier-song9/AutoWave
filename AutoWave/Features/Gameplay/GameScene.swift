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

    private let beatmap: Beatmap
    private let judgmentEngine: JudgmentEngine
    private let playbackTime: () -> TimeInterval
    private let playbackFinished: () -> Bool
    private let onComplete: () -> Void
    private let noteColor: SKColor
    private let scrollSpeed: CGFloat
    private let lastNoteTime: TimeInterval?

    private var noteNodes: [DropletNode] = []
    private var separatorNodes: [SKShapeNode] = []
    private let hitLineNode = SKShapeNode()
    private var hitLineY: CGFloat = 0
    private var hasCompleted = false

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

        if playbackFinished() || (lastNoteTime.map { time >= $0 + 2 } ?? false) {
            hasCompleted = true
            onComplete()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, size.width > 0 else { return }

        let location = touch.location(in: self)
        let lane = min(max(Int(location.x / (size.width / 4)), 0), 3)
        let time = playbackTime()

        guard let result = judgmentEngine.tap(lane: lane, at: time) else { return }

        consumeNearestVisual(lane: lane, at: time)
        showJudgment(result)
        if result.judgment != .miss {
            showSplash(at: CGPoint(x: (CGFloat(lane) + 0.5) * size.width / 4, y: hitLineY))
        }
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
