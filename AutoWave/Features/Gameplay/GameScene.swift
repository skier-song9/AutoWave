import Foundation
import SpriteKit
import UIKit

enum GameplayHaptic: Sendable {
    case perfect
    case light
    case warning
}

private func makeColor(for rgb: RGB, alpha: CGFloat = 1) -> SKColor {
    SKColor(
        red: CGFloat(rgb.r),
        green: CGFloat(rgb.g),
        blue: CGFloat(rgb.b),
        alpha: alpha
    )
}

final class GameScene: SKScene, @unchecked Sendable {
    private final class TapNoteNode: SKNode {
        let note: Note

        private let body = SKShapeNode()
        private let noteHeight: CGFloat = 22
        private let cornerRadius: CGFloat = 8

        var isConsumed = false

        init(note: Note, fillColor: SKColor, strokeColor: SKColor) {
            self.note = note
            super.init()

            body.fillColor = fillColor
            body.strokeColor = strokeColor
            body.lineWidth = 2

            addChild(body)
            zPosition = 3
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateLayout(laneWidth: CGFloat) {
            let noteWidth = laneWidth * 0.62
            let rect = CGRect(
                x: -noteWidth / 2,
                y: -noteHeight / 2,
                width: noteWidth,
                height: noteHeight
            )
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            body.path = path
        }

        func update(
            playbackTime: TimeInterval,
            hitLineY: CGFloat,
            laneOriginX: CGFloat,
            laneWidth: CGFloat,
            scrollSpeed: CGFloat,
            sceneHeight: CGFloat
        ) {
            let timeToHit = note.time - playbackTime
            let y = hitLineY + CGFloat(timeToHit) * scrollSpeed

            guard !isConsumed, playbackTime <= note.time + 0.150 else {
                isHidden = true
                return
            }

            let halfNoteHeight = noteHeight * 0.5
            guard y <= sceneHeight + halfNoteHeight, y >= -halfNoteHeight else {
                isHidden = true
                return
            }

            isHidden = false
            position = CGPoint(
                x: laneOriginX + (CGFloat(note.lane) + 0.5) * laneWidth,
                y: y
            )
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

        private let bodyColor: SKColor
        private let bodyBandColor: SKColor
        private let inactiveBandColor: SKColor
        private let inactiveCoreColor: SKColor
        private let band = SKShapeNode()
        private let core = SKShapeNode()
        private let completedBand = SKShapeNode()
        private let completedCore = SKShapeNode()
        private let remainingBand = SKShapeNode()
        private let remainingCore = SKShapeNode()
        private let headCap = SKShapeNode()
        private let tailCap = SKShapeNode()
        private let crest = SKShapeNode()

        private let capHeight: CGFloat = 22
        private let capCornerRadius: CGFloat = 8

        private var state: State = .pending
        private var fingerOn = false
        private var spinePoints: [SpinePoint] = []
        private var laneOriginX: CGFloat = 0
        private var laneWidth: CGFloat = 0
        private var scrollSpeed: CGFloat = 0
        private var breakOffset: TimeInterval?

        init(
            note: Note,
            bodyColor: SKColor,
            capColor: SKColor,
            capStrokeColor: SKColor
        ) {
            self.note = note
            self.bodyColor = bodyColor
            bodyBandColor = bodyColor.withAlphaComponent(0.5)
            inactiveBandColor = SKColor(white: 0.55, alpha: 0.25)
            inactiveCoreColor = SKColor(white: 0.65, alpha: 0.25)
            super.init()

            band.zPosition = 0
            core.zPosition = 1
            completedBand.zPosition = 0
            completedCore.zPosition = 1
            remainingBand.zPosition = 0
            remainingCore.zPosition = 1

            headCap.fillColor = capColor
            headCap.strokeColor = capStrokeColor
            headCap.lineWidth = 2
            headCap.zPosition = 2

            tailCap.fillColor = capColor
            tailCap.strokeColor = capStrokeColor
            tailCap.lineWidth = 2
            tailCap.zPosition = 2

            crest.fillColor = bodyColor
            crest.strokeColor = .clear
            crest.glowWidth = 8
            crest.zPosition = 3
            crest.isHidden = true

            addChild(band)
            addChild(core)
            addChild(completedBand)
            addChild(completedCore)
            addChild(remainingBand)
            addChild(remainingCore)
            addChild(headCap)
            addChild(tailCap)
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

        func updateLayout(laneOriginX: CGFloat, laneWidth: CGFloat, scrollSpeed: CGFloat) {
            self.laneOriginX = laneOriginX
            self.laneWidth = laneWidth
            self.scrollSpeed = scrollSpeed
            band.lineWidth = laneWidth * 0.45
            core.lineWidth = 2
            completedBand.lineWidth = band.lineWidth
            completedCore.lineWidth = core.lineWidth
            remainingBand.lineWidth = band.lineWidth
            remainingCore.lineWidth = core.lineWidth
            let capWidth = laneWidth * 0.62
            let capRect = CGRect(
                x: -capWidth / 2,
                y: -capHeight / 2,
                width: capWidth,
                height: capHeight
            )
            let capPath = CGPath(
                roundedRect: capRect,
                cornerWidth: capCornerRadius,
                cornerHeight: capCornerRadius,
                transform: nil
            )
            headCap.path = capPath
            tailCap.path = capPath
            crest.path = CGPath(
                roundedRect: CGRect(
                    x: -laneWidth * 0.225,
                    y: -4,
                    width: laneWidth * 0.45,
                    height: 8
                ),
                cornerWidth: 4,
                cornerHeight: 4,
                transform: nil
            )
            spinePoints = makeSpinePoints()
            applyPaths()
        }

        func markActivated() {
            state = .active
            fingerOn = true
            crest.isHidden = false
            crest.position = point(at: 0)
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
            tailCap.fillColor = inactiveBandColor
            tailCap.strokeColor = inactiveCoreColor
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
            band.strokeColor = inactiveBandColor
            core.strokeColor = inactiveCoreColor
            headCap.fillColor = inactiveBandColor
            headCap.strokeColor = inactiveCoreColor
            tailCap.fillColor = inactiveBandColor
            tailCap.strokeColor = inactiveCoreColor
            crest.isHidden = true
        }

        func update(
            playbackTime: TimeInterval,
            hitLineY: CGFloat,
            sceneHeight: CGFloat
        ) {
            let positions = GameplayLayout.ribbonPositions(
                hitLineY: hitLineY,
                timeToHit: note.time - playbackTime,
                duration: note.duration,
                scrollSpeed: scrollSpeed
            )
            position.y = positions.head

            if state == .pending, playbackTime > note.time + 0.150 {
                markInactive()
            }

            let endY = positions.tail
            let visibilityPadding = capHeight * 0.5
            let visible = max(position.y, endY) >= -visibilityPadding
                && min(position.y, endY) <= sceneHeight + visibilityPadding
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

            var points = [SpinePoint]()
            points.reserveCapacity(note.lanePath.count + 2)
            points.append(spinePoint(at: 0))
            for keyframe in note.lanePath where keyframe.offset > 0 && keyframe.offset < note.duration {
                points.append(spinePoint(at: keyframe.offset))
            }
            if points.last?.offset != note.duration {
                points.append(spinePoint(at: note.duration))
            }
            return points
        }

        private func spinePoint(at offset: TimeInterval) -> SpinePoint {
            SpinePoint(
                offset: offset,
                point: CGPoint(
                    x: laneOriginX + (CGFloat(lane(at: offset)) + 0.5) * laneWidth,
                    y: CGFloat(offset) * scrollSpeed
                )
            )
        }

        private func applyPaths() {
            band.path = straightPath(from: spinePoints)
            core.path = band.path
            band.strokeColor = bodyBandColor
            core.strokeColor = bodyColor
            band.isHidden = false
            core.isHidden = false
            completedBand.isHidden = true
            completedCore.isHidden = true
            remainingBand.isHidden = true
            remainingCore.isHidden = true
            headCap.position = spinePoints.first?.point ?? .zero
            tailCap.position = spinePoints.last?.point ?? .zero
            headCap.isHidden = false
            tailCap.isHidden = false

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
            completedBand.path = straightPath(from: completed)
            completedCore.path = completedBand.path
            completedBand.strokeColor = bodyBandColor
            completedCore.strokeColor = bodyColor
            remainingBand.path = straightPath(from: remaining)
            remainingCore.path = remainingBand.path
            remainingBand.strokeColor = inactiveBandColor
            remainingCore.strokeColor = inactiveCoreColor
            completedBand.isHidden = false
            completedCore.isHidden = false
            remainingBand.isHidden = false
            remainingCore.isHidden = false
        }

        private func straightPath(from points: [SpinePoint]) -> CGPath? {
            guard let first = points.first else { return nil }

            let path = CGMutablePath()
            path.move(to: first.point)
            for index in 1..<points.count {
                path.addLine(to: points[index].point)
            }
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

    private final class HitPopNode: SKNode {
        private let ring = SKShapeNode()
        private let particles: [SKShapeNode]
        private let directions: [CGVector]
        private var age: TimeInterval = 0
        private var intensity: CGFloat = 1
        private var isActive = false

        init(color: SKColor) {
            directions = (0..<6).map { index in
                let angle = Double(index) * .pi / 3
                return CGVector(dx: CGFloat(cos(angle)), dy: CGFloat(sin(angle)))
            }
            particles = (0..<6).map { _ in
                let particle = SKShapeNode(circleOfRadius: 2)
                particle.fillColor = color
                particle.strokeColor = .clear
                particle.isHidden = true
                return particle
            }
            super.init()

            ring.fillColor = color.withAlphaComponent(0.12)
            ring.strokeColor = color
            ring.lineWidth = 2
            addChild(ring)
            for particle in particles {
                addChild(particle)
            }
            zPosition = 8
            isHidden = true
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateLayout(noteWidth: CGFloat) {
            ring.path = CGPath(
                roundedRect: CGRect(
                    x: -noteWidth / 2,
                    y: -11,
                    width: noteWidth,
                    height: 22
                ),
                cornerWidth: 8,
                cornerHeight: 8,
                transform: nil
            )
        }

        func trigger(at point: CGPoint, intensity: CGFloat) {
            self.intensity = intensity
            age = 0
            isActive = true
            isHidden = false
            position = point
            ring.alpha = 1
            ring.setScale(1)
            for particle in particles {
                particle.position = .zero
                particle.alpha = 1
                particle.setScale(1)
                particle.isHidden = false
            }
        }

        func update(delta: TimeInterval) {
            guard isActive else { return }

            age += delta
            let progress = min(max(age / 0.32, 0), 1)
            let fade = CGFloat(1 - progress)
            ring.setScale(1 + 2.4 * CGFloat(progress) * intensity)
            ring.alpha = fade

            let distance = 34 * CGFloat(progress)
            for index in particles.indices {
                let direction = directions[index]
                particles[index].position = CGPoint(
                    x: direction.dx * distance,
                    y: direction.dy * distance
                )
                particles[index].alpha = fade
            }

            guard progress < 1 else {
                isActive = false
                isHidden = true
                return
            }
        }
    }

    private struct RippleState {
        var isActive = false
        var age: TimeInterval = 0
        var duration: TimeInterval = 2.4
        var maxRadius: CGFloat = 0
    }

    private let beatmap: Beatmap
    private let judgmentEngine: JudgmentEngine
    private let visualizerTap: VisualizerTap
    private let playbackTime: @Sendable () -> TimeInterval
    private let playbackFinished: @Sendable () -> Bool
    private let onComplete: (Bool) -> Void
    private let onHaptic: (GameplayHaptic) -> Void
    private let theme: GameTheme
    private let tapNoteColor: SKColor
    private let tapNoteStrokeColor: SKColor
    private let dragBodyColor: SKColor
    private let dragCapColor: SKColor
    private let laneLineColor: SKColor
    private let rippleColor: SKColor
    private let judgmentAccentColor: SKColor
    private let scrollSpeed: CGFloat
    private let laneCount: Int
    private let completionFallbackTime: TimeInterval

    private var noteNodes: [TapNoteNode] = []
    private var ribbonNodes: [RibbonNode] = []
    private var gradientNodes: [SKSpriteNode] = []
    private var laneFillNodes: [SKShapeNode] = []
    private var boundaryNodes: [SKShapeNode] = []
    private var receptorNodes: [SKShapeNode] = []
    private var receptorFlashRemaining: [TimeInterval] = []
    private var hitPopNodes: [HitPopNode] = []
    private var rippleNodes: [SKShapeNode] = []
    private var rippleStates = Array(repeating: RippleState(), count: 6)
    private let backgroundOverlayNode = SKShapeNode()
    private let hitLineNode = SKShapeNode()
    private let comboCaptionLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let comboValueLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let latestJudgmentLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let scoreCaptionLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let scoreValueLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let lifeCaptionLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let lifeGaugeTrack = SKShapeNode()
    private let lifeGaugeFill = SKShapeNode()
    private let gameOverLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var laneAreaRect = CGRect.zero
    private var laneWidth: CGFloat = 0
    private var hitLineY: CGFloat = 0
    private var scrollSpeedMultiplier: CGFloat = 1
    private var nextRippleIndex = 0
    private var nextRippleSpawnTime: TimeInterval = 0.25
    private var sceneStartTime: TimeInterval?
    private var lastFrameTime: TimeInterval?
    private var hasCompleted = false
    private var visualizerBands = [Float](repeating: 0, count: VisualizerTap.bandCount)
    private var visualizerGeneration: UInt64 = 0
    private var activeDragTouchID: ObjectIdentifier?
    private var activeDragNoteID: UUID?
    private var activeDragTouchLane: Double?
    private var nextDragTickTime: TimeInterval?
    private let dragTickInterval: TimeInterval = 0.1
    private var nextHitPopIndex = 0
    private var lastRenderedCombo: Int?
    private var lastRenderedScore: Int?
    private var lastRenderedLife: Int?
    private var comboPulseRemaining: TimeInterval = 0
    private var gameOverFlashRemaining: TimeInterval = 0
    private var isGameOverPending = false
    private var latestJudgmentTime: TimeInterval?
    private var lastFrameDelta: TimeInterval = 0
    private let gameOverFlashDuration: TimeInterval = 0.32
    private let judgmentFadeDelay: TimeInterval = 0.6
    private let judgmentFadeDuration: TimeInterval = 0.2
    init(
        beatmap: Beatmap,
        difficulty: Difficulty,
        judgmentEngine: JudgmentEngine,
        visualizerTap: VisualizerTap,
        playbackTime: @escaping @Sendable () -> TimeInterval,
        playbackFinished: @escaping @Sendable () -> Bool,
        audioDuration: TimeInterval,
        onComplete: @escaping (Bool) -> Void,
        onHaptic: @escaping (GameplayHaptic) -> Void
    ) {
        self.beatmap = beatmap
        self.judgmentEngine = judgmentEngine
        self.visualizerTap = visualizerTap
        self.playbackTime = playbackTime
        self.playbackFinished = playbackFinished
        self.onComplete = onComplete
        self.onHaptic = onHaptic
        let selectedTheme = GameTheme.preset(id: beatmap.themeID)
        theme = selectedTheme
        tapNoteColor = makeColor(for: selectedTheme.tapNote)
        tapNoteStrokeColor = makeColor(for: selectedTheme.tapNoteStroke)
        dragBodyColor = makeColor(for: selectedTheme.dragBody)
        dragCapColor = makeColor(for: selectedTheme.dragCap)
        laneLineColor = makeColor(for: selectedTheme.laneLine)
        rippleColor = makeColor(for: selectedTheme.ripple)
        judgmentAccentColor = makeColor(for: selectedTheme.judgmentAccent)
        scrollSpeed = CGFloat(DifficultyProfile.profile(for: difficulty).scrollSpeed)
        laneCount = min(max(beatmap.laneCount, 4), 7)
        let lastNoteTime = beatmap.notes.reduce(0) { max($0, $1.time) }
        completionFallbackTime = max(audioDuration, lastNoteTime) + 2
        super.init(size: CGSize(width: 1, height: 1))
        scaleMode = .resizeFill
        isUserInteractionEnabled = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        backgroundColor = makeColor(for: theme.backgroundBottom)

        for index in 0..<16 {
            let progress = CGFloat(index) / 15
            let node = SKSpriteNode(color: gradientColor(at: progress), size: .zero)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.zPosition = -5
            gradientNodes.append(node)
            addChild(node)
        }

        backgroundOverlayNode.fillColor = makeColor(for: theme.backgroundTop)
        backgroundOverlayNode.strokeColor = .clear
        backgroundOverlayNode.zPosition = -2
        backgroundOverlayNode.alpha = 0
        addChild(backgroundOverlayNode)

        for _ in rippleStates.indices {
            let ripple = SKShapeNode(circleOfRadius: 1)
            ripple.fillColor = .clear
            ripple.strokeColor = rippleColor
            ripple.lineWidth = 2
            ripple.zPosition = 0.5
            ripple.isHidden = true
            rippleNodes.append(ripple)
            addChild(ripple)
        }
        spawnRipple(bass: 0.65, mid: 0.35)

        addChild(hitLineNode)
        hitLineNode.zPosition = 2
        hitLineNode.strokeColor = laneLineColor
        hitLineNode.lineWidth = 1

        receptorFlashRemaining = Array(repeating: .zero, count: laneCount)
        for _ in 0..<laneCount {
            let lane = SKShapeNode()
            lane.fillColor = makeColor(for: theme.laneFill)
            lane.strokeColor = .clear
            lane.zPosition = -3
            laneFillNodes.append(lane)
            addChild(lane)

            let receptor = SKShapeNode()
            receptor.fillColor = .clear
            receptor.strokeColor = laneLineColor
            receptor.lineWidth = 1
            receptor.zPosition = 2.5
            receptorNodes.append(receptor)
            addChild(receptor)
        }

        for _ in 0...laneCount {
            let boundary = SKShapeNode()
            boundary.strokeColor = laneLineColor
            boundary.lineWidth = 1
            boundary.zPosition = 1
            boundaryNodes.append(boundary)
            addChild(boundary)
        }

        for _ in 0..<8 {
            let hitPop = HitPopNode(color: judgmentAccentColor)
            hitPopNodes.append(hitPop)
            addChild(hitPop)
        }

        for note in beatmap.notes where note.kind == .tap {
            let node = TapNoteNode(
                note: note,
                fillColor: tapNoteColor,
                strokeColor: tapNoteStrokeColor
            )
            noteNodes.append(node)
            addChild(node)
        }

        for note in beatmap.notes where note.kind == .drag {
            let node = RibbonNode(
                note: note,
                bodyColor: dragBodyColor,
                capColor: dragCapColor,
                capStrokeColor: tapNoteStrokeColor
            )
            ribbonNodes.append(node)
            addChild(node)
        }

        configureHUD()
        updateLayout()
    }

    private func configureHUD() {
        comboCaptionLabel.text = "콤보"
        comboCaptionLabel.fontSize = 13
        comboCaptionLabel.fontColor = .white.withAlphaComponent(0.72)
        comboCaptionLabel.horizontalAlignmentMode = .center
        comboCaptionLabel.verticalAlignmentMode = .center
        comboCaptionLabel.zPosition = 12

        comboValueLabel.text = "0"
        comboValueLabel.fontSize = 34
        comboValueLabel.fontColor = .white
        comboValueLabel.horizontalAlignmentMode = .center
        comboValueLabel.verticalAlignmentMode = .center
        comboValueLabel.zPosition = 12

        latestJudgmentLabel.fontSize = 16
        latestJudgmentLabel.fontColor = judgmentAccentColor
        latestJudgmentLabel.horizontalAlignmentMode = .center
        latestJudgmentLabel.verticalAlignmentMode = .center
        latestJudgmentLabel.alpha = 0
        latestJudgmentLabel.zPosition = 12

        scoreCaptionLabel.text = "점수"
        scoreCaptionLabel.fontSize = 12
        scoreCaptionLabel.fontColor = .white.withAlphaComponent(0.72)
        scoreCaptionLabel.horizontalAlignmentMode = .center
        scoreCaptionLabel.verticalAlignmentMode = .center
        scoreCaptionLabel.zPosition = 12

        scoreValueLabel.text = "0"
        scoreValueLabel.fontSize = 22
        scoreValueLabel.fontColor = .white
        scoreValueLabel.horizontalAlignmentMode = .center
        scoreValueLabel.verticalAlignmentMode = .center
        scoreValueLabel.zPosition = 12

        lifeCaptionLabel.text = "체력"
        lifeCaptionLabel.fontSize = 12
        lifeCaptionLabel.fontColor = .white.withAlphaComponent(0.72)
        lifeCaptionLabel.horizontalAlignmentMode = .center
        lifeCaptionLabel.verticalAlignmentMode = .center
        lifeCaptionLabel.zPosition = 12

        lifeGaugeTrack.fillColor = .white.withAlphaComponent(0.12)
        lifeGaugeTrack.strokeColor = .white.withAlphaComponent(0.5)
        lifeGaugeTrack.lineWidth = 1
        lifeGaugeTrack.zPosition = 12

        lifeGaugeFill.strokeColor = .clear
        lifeGaugeFill.zPosition = 13

        gameOverLabel.text = "게임 오버"
        gameOverLabel.fontSize = 38
        gameOverLabel.fontColor = judgmentAccentColor
        gameOverLabel.horizontalAlignmentMode = .center
        gameOverLabel.verticalAlignmentMode = .center
        gameOverLabel.zPosition = 14
        gameOverLabel.isHidden = true

        addChild(comboCaptionLabel)
        addChild(comboValueLabel)
        addChild(latestJudgmentLabel)
        addChild(scoreCaptionLabel)
        addChild(scoreValueLabel)
        addChild(lifeCaptionLabel)
        addChild(lifeGaugeTrack)
        addChild(lifeGaugeFill)
        addChild(gameOverLabel)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateLayout()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !hasCompleted else { return }

        let delta = frameDelta(at: currentTime)
        if isGameOverPending {
            updateGameOverFlash(delta: delta)
            updateJudgmentLabel(at: currentTime)
            return
        }

        if let generation = visualizerTap.copyLatestSnapshot(
            ifNewerThan: visualizerGeneration,
            to: &visualizerBands
        ) {
            visualizerGeneration = generation
        }
        updateRippleField(at: currentTime, delta: delta)
        let time = playbackTime()
        judgmentEngine.advance(to: time) { [self] result in
            showJudgment(result, at: currentTime)
        }

        updateHUD()
        if judgmentEngine.isGameOver {
            beginGameOver()
            updateJudgmentLabel(at: currentTime)
            return
        }

        advanceDragTicks(to: time)
        updateHUD()

        if judgmentEngine.isGameOver {
            beginGameOver()
            return
        }

        for node in noteNodes {
            node.update(
                playbackTime: time,
                hitLineY: hitLineY,
                laneOriginX: laneAreaRect.minX,
                laneWidth: laneWidth,
                scrollSpeed: currentScrollSpeed,
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

        updateJudgmentLabel(at: currentTime)

        if playbackFinished() || time >= completionFallbackTime {
            hasCompleted = true
            onComplete(false)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isGameOverPending, !hasCompleted, !judgmentEngine.isGameOver,
              size.width > 0 else { return }

        let time = playbackTime()
        for touch in touches {
            guard let touchLane = laneCoordinate(for: touch.location(in: self)) else {
                continue
            }

            if activeDragNoteID == nil,
               let ribbon = nearestRibbon(at: time, touchLane: touchLane),
               let result = judgmentEngine.beginDrag(
                   noteID: ribbon.note.id,
                   touchLane: touchLane,
                   at: time
               ) {
                ribbon.markActivated()
                activeDragTouchID = ObjectIdentifier(touch)
                activeDragNoteID = ribbon.note.id
                activeDragTouchLane = touchLane
                let lane = laneIndex(for: ribbon.note.lane)
                flashReceptor(lane)
                showJudgment(result, at: CACurrentMediaTime())
                if result.judgment != .miss {
                    showHitPop(at: receptorPoint(for: lane), judgment: result.judgment)
                }
                continue
            }

            let lane = laneIndex(for: touchLane)

            guard let result = judgmentEngine.tap(lane: lane, at: time) else { continue }

            consumeNearestVisual(lane: lane, at: time)
            showJudgment(result, at: CACurrentMediaTime())
            if result.judgment != .miss {
                flashReceptor(lane)
                showHitPop(at: receptorPoint(for: lane), judgment: result.judgment)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isGameOverPending, !hasCompleted, !judgmentEngine.isGameOver else { return }

        for touch in touches {
            guard let activeDragTouchID,
                  ObjectIdentifier(touch) == activeDragTouchID else {
                continue
            }

            activeDragTouchLane = laneCoordinate(for: touch.location(in: self))
            if let activeDragNoteID, let ribbon = ribbonNode(for: activeDragNoteID) {
                ribbon.setFingerOn(activeDragTouchLane != nil)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateEndedDragTouch(in: touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateEndedDragTouch(in: touches)
    }

    func setScrollSpeedMultiplier(_ multiplier: CGFloat) {
        scrollSpeedMultiplier = min(max(multiplier, 0.5), 1.25)
        for node in ribbonNodes {
            node.updateLayout(
                laneOriginX: laneAreaRect.minX,
                laneWidth: laneWidth,
                scrollSpeed: currentScrollSpeed
            )
        }
    }

    private func updateLayout() {
        guard size.width > 0, size.height > 0 else { return }

        let stripHeight = size.height / CGFloat(max(gradientNodes.count, 1))
        for (index, node) in gradientNodes.enumerated() {
            node.size = CGSize(width: size.width, height: stripHeight + 1)
            node.position = CGPoint(x: size.width / 2, y: CGFloat(index) * stripHeight)
        }

        backgroundOverlayNode.path = CGPath(
            rect: CGRect(origin: .zero, size: size),
            transform: nil
        )

        laneAreaRect = GameplayLayout.laneAreaRect(in: size)
        let usableWidth = laneAreaRect.width
        laneWidth = usableWidth / CGFloat(laneCount)
        let laneFillColor = makeColor(for: theme.laneFill)
        for (index, lane) in laneFillNodes.enumerated() {
            lane.path = CGPath(
                rect: CGRect(
                    x: laneAreaRect.minX + CGFloat(index) * laneWidth,
                    y: 0,
                    width: laneWidth,
                    height: size.height
                ),
                transform: nil
            )
            lane.fillColor = laneFillColor
            lane.alpha = index.isMultiple(of: 2)
                ? CGFloat(theme.laneFillAlpha)
                : CGFloat(theme.laneFillAlpha * 0.6)
        }

        hitLineY = GameplayLayout.hitLineY(in: size)
        let hitLinePath = CGMutablePath()
        hitLinePath.move(to: CGPoint(x: laneAreaRect.minX, y: hitLineY))
        hitLinePath.addLine(to: CGPoint(x: laneAreaRect.maxX, y: hitLineY))
        hitLineNode.path = hitLinePath

        for (index, boundary) in boundaryNodes.enumerated() {
            let path = CGMutablePath()
            let x = laneAreaRect.minX + CGFloat(index) * laneWidth
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            boundary.path = path
            boundary.strokeColor = laneLineColor
            boundary.lineWidth = 1
            boundary.alpha = CGFloat(theme.laneLineAlpha)
        }

        let receptorRect = CGRect(
            x: -laneWidth * 0.31,
            y: -11,
            width: laneWidth * 0.62,
            height: 22
        )
        let receptorPath = CGPath(
            roundedRect: receptorRect,
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        )
        for (index, receptor) in receptorNodes.enumerated() {
            receptor.path = receptorPath
            receptor.position = CGPoint(
                x: laneAreaRect.minX + (CGFloat(index) + 0.5) * laneWidth,
                y: hitLineY
            )
            receptor.strokeColor = laneLineColor
            receptor.alpha = 1
        }

        let rippleCenter = CGPoint(x: laneAreaRect.midX, y: size.height * 0.22)
        for ripple in rippleNodes {
            ripple.position = rippleCenter
        }

        let hudTopMargin = max(size.height * 0.06, 54)
        comboCaptionLabel.position = CGPoint(x: laneAreaRect.midX, y: size.height - hudTopMargin)
        comboValueLabel.position = CGPoint(x: laneAreaRect.midX, y: size.height - hudTopMargin - 48)
        latestJudgmentLabel.position = CGPoint(x: laneAreaRect.midX, y: size.height - hudTopMargin - 96)
        scoreCaptionLabel.position = CGPoint(x: laneAreaRect.minX / 2, y: size.height * 0.10 + 16)
        scoreValueLabel.position = CGPoint(x: laneAreaRect.minX / 2, y: size.height * 0.10 - 10)

        let lifeCenterX = laneAreaRect.maxX + (size.width - laneAreaRect.maxX) / 2
        let gaugeHeight = min(max(size.height * 0.45, 100), 190)
        let gaugeBottom = size.height * 0.18
        let gaugeRect = CGRect(x: -8, y: 0, width: 16, height: gaugeHeight)
        let gaugeCornerRadius = min(8, min(gaugeRect.width, gaugeRect.height) / 2)
        let gaugePath = CGPath(
            roundedRect: gaugeRect,
            cornerWidth: gaugeCornerRadius,
            cornerHeight: gaugeCornerRadius,
            transform: nil
        )
        lifeGaugeTrack.path = gaugePath
        lifeGaugeFill.path = gaugePath
        lifeGaugeTrack.position = CGPoint(x: lifeCenterX, y: gaugeBottom)
        lifeGaugeFill.position = CGPoint(x: lifeCenterX, y: gaugeBottom)
        lifeCaptionLabel.position = CGPoint(x: lifeCenterX, y: gaugeBottom + gaugeHeight + 16)
        gameOverLabel.position = CGPoint(x: laneAreaRect.midX, y: size.height * 0.52)

        for node in noteNodes {
            node.updateLayout(laneWidth: laneWidth)
        }
        for node in ribbonNodes {
            node.updateLayout(
                laneOriginX: laneAreaRect.minX,
                laneWidth: laneWidth,
                scrollSpeed: currentScrollSpeed
            )
        }
        for node in hitPopNodes {
            node.updateLayout(noteWidth: laneWidth * 0.62)
        }

        lastRenderedLife = nil
        updateHUD()
    }

    private var currentScrollSpeed: CGFloat {
        scrollSpeed * scrollSpeedMultiplier
    }

    private func frameDelta(at currentTime: TimeInterval) -> TimeInterval {
        let delta = min(max(currentTime - (lastFrameTime ?? currentTime), 0), 0.1)
        lastFrameTime = currentTime
        lastFrameDelta = delta
        return delta
    }

    private func updateRippleField(at currentTime: TimeInterval, delta: TimeInterval) {
        if sceneStartTime == nil {
            sceneStartTime = currentTime
        }

        updateReceptorFlashes(delta: delta)
        for hitPop in hitPopNodes {
            hitPop.update(delta: delta)
        }

        let bass = bandMean(visualizerBands, from: 0, to: 4)
        let mid = bandMean(visualizerBands, from: 4, to: 10)
        let overall = bandMean(visualizerBands, from: 0, to: visualizerBands.count)
        let washIn = min(
            max((currentTime - (sceneStartTime ?? currentTime)) / 0.8, 0),
            1
        )
        backgroundOverlayNode.alpha = max(0.025 + overall * 0.16, washIn * 0.8)

        if currentTime >= nextRippleSpawnTime {
            spawnRipple(bass: bass, mid: mid)
            nextRippleSpawnTime = currentTime + 0.34 - bass * 0.21
        }

        for index in rippleStates.indices {
            guard rippleStates[index].isActive else { continue }

            rippleStates[index].age += delta
            let progress = min(
                max(rippleStates[index].age / rippleStates[index].duration, 0),
                1
            )
            let ripple = rippleNodes[index]
            if progress >= 1 {
                rippleStates[index].isActive = false
                ripple.isHidden = true
                continue
            }

            ripple.isHidden = false
            ripple.setScale(8 + rippleStates[index].maxRadius * CGFloat(progress))
            ripple.lineWidth = 1 + mid * 3.5
            ripple.alpha = (1 - CGFloat(progress)) * (0.18 + mid * 0.42)
        }
    }

    private func spawnRipple(bass: CGFloat, mid: CGFloat) {
        guard !rippleNodes.isEmpty else { return }

        let index = nextRippleIndex
        nextRippleIndex = (nextRippleIndex + 1) % rippleNodes.count

        let radius = max(size.width, size.height)
            * (0.38 + bass * 0.68)
        rippleStates[index] = RippleState(
            isActive: true,
            age: 0,
            duration: 2.1 + TimeInterval(bass) * 1.2,
            maxRadius: radius
        )
        let ripple = rippleNodes[index]
        ripple.isHidden = false
        ripple.setScale(8)
        ripple.lineWidth = 1 + mid * 3.5
        ripple.alpha = 0.18 + mid * 0.42
    }

    private func updateReceptorFlashes(delta: TimeInterval) {
        for index in receptorNodes.indices {
            let remaining = max(receptorFlashRemaining[index] - delta, 0)
            receptorFlashRemaining[index] = remaining
            let receptor = receptorNodes[index]
            if remaining == 0 {
                receptor.strokeColor = laneLineColor
                receptor.alpha = 1
            } else {
                receptor.strokeColor = judgmentAccentColor
                receptor.alpha = CGFloat(0.45 + 0.55 * (remaining / 0.18))
            }
        }
    }

    private func flashReceptor(_ lane: Int) {
        guard receptorNodes.indices.contains(lane) else { return }
        receptorFlashRemaining[lane] = 0.18
        receptorNodes[lane].strokeColor = judgmentAccentColor
        receptorNodes[lane].alpha = 1
    }

    private func bandMean(_ bands: [Float], from start: Int, to end: Int) -> CGFloat {
        guard start < end, start >= 0, end <= bands.count else { return 0 }

        var total: Float = 0
        for index in start..<end {
            total += bands[index]
        }
        return CGFloat(total / Float(end - start))
    }

    private func gradientColor(at progress: CGFloat) -> SKColor {
        let amount = min(max(progress, 0), 1)
        let top = theme.backgroundTop
        let bottom = theme.backgroundBottom
        return makeColor(
            for: RGB(
                r: bottom.r + (top.r - bottom.r) * Double(amount),
                g: bottom.g + (top.g - bottom.g) * Double(amount),
                b: bottom.b + (top.b - bottom.b) * Double(amount)
            )
        )
    }

    private func advanceDragTicks(to time: TimeInterval) {
        guard !isGameOverPending, !hasCompleted, !judgmentEngine.isGameOver else { return }

        if nextDragTickTime == nil {
            nextDragTickTime = (floor(time / dragTickInterval) + 1) * dragTickInterval
        }

        while !judgmentEngine.isGameOver,
              let tickTime = nextDragTickTime,
              tickTime <= time + 0.000_000_001 {
            processDragTick(at: tickTime)
            nextDragTickTime = tickTime + dragTickInterval
        }
    }

    private func processDragTick(at time: TimeInterval) {
        guard !isGameOverPending, !hasCompleted, !judgmentEngine.isGameOver,
              let noteID = activeDragNoteID else { return }

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
            onHaptic(.warning)
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

    private func laneCoordinate(for point: CGPoint) -> Double? {
        GameplayLayout.laneCoordinate(
            for: point,
            in: laneAreaRect,
            laneWidth: laneWidth
        )
    }

    private func laneIndex(for coordinate: Double) -> Int {
        min(max(Int(coordinate.rounded()), 0), laneCount - 1)
    }

    private func receptorPoint(for lane: Int) -> CGPoint {
        CGPoint(
            x: laneAreaRect.minX + (CGFloat(lane) + 0.5) * laneWidth,
            y: hitLineY
        )
    }

    private func updateEndedDragTouch(in touches: Set<UITouch>) {
        guard !isGameOverPending, !hasCompleted, !judgmentEngine.isGameOver else { return }

        for touch in touches {
            guard let activeDragTouchID,
                  ObjectIdentifier(touch) == activeDragTouchID else {
                continue
            }

            activeDragTouchLane = nil
            if let activeDragNoteID, let ribbon = ribbonNode(for: activeDragNoteID) {
                ribbon.setFingerOn(false)
            }
            processDragTick(at: playbackTime())
            break
        }
    }

    private func clearActiveDrag() {
        activeDragTouchID = nil
        activeDragNoteID = nil
        activeDragTouchLane = nil
    }

    private func consumeNearestVisual(lane: Int, at time: TimeInterval) {
        var nearest: TapNoteNode?
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

    private func showJudgment(_ result: JudgmentResult, at time: TimeInterval) {
        let judgmentText: String
        switch result.judgment {
        case .perfect:
            judgmentText = "퍼펙트"
            onHaptic(.perfect)
        case .great:
            judgmentText = "그레이트"
            onHaptic(.light)
        case .good:
            judgmentText = "굿"
            onHaptic(.light)
        case .bad:
            judgmentText = "배드"
            onHaptic(.light)
        case .miss:
            judgmentText = "미스"
        }

        latestJudgmentLabel.text = judgmentText
        latestJudgmentLabel.alpha = 1
        latestJudgmentTime = time
        comboPulseRemaining = 0.18
        comboValueLabel.setScale(1.12)
    }

    private func updateJudgmentLabel(at time: TimeInterval) {
        guard let latestJudgmentTime else { return }

        let elapsed = max(time - latestJudgmentTime, 0)
        guard elapsed > judgmentFadeDelay else {
            latestJudgmentLabel.alpha = 1
            return
        }

        let fade = 1 - min((elapsed - judgmentFadeDelay) / judgmentFadeDuration, 1)
        latestJudgmentLabel.alpha = CGFloat(fade)
        if fade <= 0 {
            self.latestJudgmentTime = nil
        }
    }

    private func showHitPop(at point: CGPoint, judgment: Judgment) {
        guard !hitPopNodes.isEmpty else { return }

        let intensity: CGFloat
        switch judgment {
        case .perfect:
            intensity = 1
        case .great:
            intensity = 0.86
        case .good:
            intensity = 0.7
        case .bad, .miss:
            intensity = 0.55
        }

        hitPopNodes[nextHitPopIndex].trigger(at: point, intensity: intensity)
        nextHitPopIndex = (nextHitPopIndex + 1) % hitPopNodes.count
    }

    private func updateHUD() {
        let combo = judgmentEngine.combo
        if combo != lastRenderedCombo {
            comboValueLabel.text = "\(combo)"
            lastRenderedCombo = combo
        }

        let score = judgmentEngine.score
        if score != lastRenderedScore {
            scoreValueLabel.text = "\(score)"
            lastRenderedScore = score
        }

        let life = judgmentEngine.life
        if life <= 0 {
            lifeGaugeFill.yScale = 0
            lifeGaugeFill.isHidden = true
            lastRenderedLife = life
        } else if life != lastRenderedLife {
            let fraction = CGFloat(life) / 100
            lifeGaugeFill.xScale = 1
            lifeGaugeFill.yScale = fraction
            lifeGaugeFill.fillColor = lifeGaugeColor(for: fraction)
            lifeGaugeFill.isHidden = false
            lastRenderedLife = life
        }

        comboPulseRemaining = max(comboPulseRemaining - lastFrameDelta, 0)
        let pulse = comboPulseRemaining / 0.18
        comboValueLabel.setScale(1 + 0.12 * CGFloat(pulse))
    }

    private func lifeGaugeColor(for fraction: CGFloat) -> SKColor {
        if fraction >= 0.5 {
            let progress = (fraction - 0.5) * 2
            return SKColor(
                red: 1 - 0.8 * progress,
                green: 0.72 + 0.18 * progress,
                blue: 0.18 + 0.17 * progress,
                alpha: 1
            )
        }

        let progress = fraction * 2
        return SKColor(
            red: 1,
            green: 0.12 + 0.60 * progress,
            blue: 0.10 + 0.08 * progress,
            alpha: 1
        )
    }

    private func beginGameOver() {
        guard !isGameOverPending else { return }
        isGameOverPending = true
        clearActiveDrag()
        gameOverFlashRemaining = gameOverFlashDuration
        gameOverLabel.isHidden = false
        gameOverLabel.alpha = 1
        gameOverLabel.setScale(1)
    }

    private func updateGameOverFlash(delta: TimeInterval) {
        gameOverFlashRemaining = max(gameOverFlashRemaining - delta, 0)
        let progress = 1 - gameOverFlashRemaining / gameOverFlashDuration
        gameOverLabel.alpha = CGFloat(max(0, 1 - progress))
        gameOverLabel.setScale(1 + 0.18 * CGFloat(progress))

        guard gameOverFlashRemaining == 0 else { return }

        hasCompleted = true
        onComplete(true)
    }
}
