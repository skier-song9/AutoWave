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
    private func makeScanlineTexture() -> SKTexture {
        let size = CGSize(width: 4, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            rendererContext.cgContext.setFillColor(UIColor.white.cgColor)
            for y in stride(from: 0, to: Int(size.height), by: 2) {
                rendererContext.cgContext.fill(CGRect(x: 0, y: CGFloat(y), width: size.width, height: 1))
            }
        }
        return SKTexture(image: image)
    }

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
            projection: PerspectiveProjection,
            scrollSpeed: CGFloat,
            sceneHeight: CGFloat
        ) {
            let timeToHit = note.time - playbackTime
            let progress = projection.progress(
                timeToHit: timeToHit,
                scrollSpeed: scrollSpeed
            )
            let point = projection.point(lane: note.lane, at: progress)
            let scale = projection.scale(at: progress)

            guard !isConsumed, playbackTime <= note.time + 0.150 else {
                isHidden = true
                return
            }

            let halfNoteHeight = noteHeight * scale * 0.5
            guard point.y <= sceneHeight + halfNoteHeight, point.y >= -halfNoteHeight else {
                isHidden = true
                return
            }

            isHidden = false
            position = point
            setScale(scale)
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
            let lane: Double
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
        private let crest = SKShapeNode()
        private let cropNode = SKCropNode()
        private let cropMask = SKShapeNode()

        private let capHeight: CGFloat = 22
        private let capCornerRadius: CGFloat = 8

        private var state: State = .pending
        private var fingerOn = false
        private var spinePoints: [SpinePoint] = []
        private var projection: PerspectiveProjection?
        private var laneWidth: CGFloat = 0
        private var scrollSpeed: CGFloat = 0
        private var sceneHeight: CGFloat = 0
        private var breakOffset: TimeInterval?
        private var glowPulseRemaining: TimeInterval = 0

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

            crest.fillColor = bodyColor
            crest.strokeColor = .clear
            crest.glowWidth = 8
            crest.zPosition = 3
            crest.isHidden = true

            cropMask.fillColor = .white
            cropMask.strokeColor = .clear
            cropNode.maskNode = cropMask
            cropNode.addChild(band)
            cropNode.addChild(core)
            cropNode.addChild(completedBand)
            cropNode.addChild(completedCore)
            cropNode.addChild(remainingBand)
            cropNode.addChild(remainingCore)
            cropNode.addChild(headCap)
            cropNode.addChild(crest)
            addChild(cropNode)
            zPosition = 1.5
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func canBegin(at time: TimeInterval, touchLane: Double) -> Bool {
            guard state == .pending else { return false }
            let timeOffset = abs(note.time - time)
            let elapsed = max(time - note.time, 0)
            return timeOffset <= 0.150
                && abs(touchLane - lane(at: 0)) <= laneTolerance(at: elapsed)
        }

        func updateLayout(
            projection: PerspectiveProjection,
            scrollSpeed: CGFloat,
            sceneHeight: CGFloat
        ) {
            self.projection = projection
            self.laneWidth = projection.bottomLaneWidth
            self.scrollSpeed = scrollSpeed
            self.sceneHeight = sceneHeight
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
            cropMask.path = CGPath(
                rect: CGRect(
                    x: -laneWidth * CGFloat(projection.laneCount) * 8,
                    y: 0,
                    width: laneWidth * CGFloat(projection.laneCount) * 16,
                    height: max(sceneHeight * 2, 1_000)
                ),
                transform: nil
            )
            spinePoints = makeSpinePoints()
            applyPaths(at: 0)
        }

        func markActivated(at time: TimeInterval) {
            state = .active
            fingerOn = true
            glowPulseRemaining = 0.18
            headCap.isHidden = true
            crest.isHidden = false
            crest.position = point(at: 0, playbackTime: time)
        }

        func setFingerOn(_ isOn: Bool) {
            guard state == .active else { return }
            fingerOn = isOn
        }

        func markScored(at time: TimeInterval) {
            guard state == .active else { return }
            fingerOn = true
            glowPulseRemaining = 0.12
            crest.isHidden = false
            crest.position = point(
                at: max(time - note.time, 0),
                playbackTime: time
            )
        }

        func markBroken(at time: TimeInterval) {
            state = .broken
            fingerOn = false
            breakOffset = min(max(time - note.time, 0), note.duration)
            cropMask.position.y = 0
            cropNode.isHidden = false
            applyPaths(at: time)
            crest.isHidden = true
        }

        func markFinished() {
            state = .finished
            fingerOn = false
            headCap.isHidden = true
            band.isHidden = true
            core.isHidden = true
            completedBand.isHidden = true
            completedCore.isHidden = true
            remainingBand.isHidden = true
            remainingCore.isHidden = true
            cropNode.isHidden = true
            isHidden = true
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
            cropMask.position.y = 0
            cropNode.isHidden = false
            crest.isHidden = true
        }

        func update(
            playbackTime: TimeInterval,
            delta: TimeInterval
        ) {
            guard let projection else { return }

            let headProgress = projection.progress(
                timeToHit: note.time - playbackTime,
                scrollSpeed: scrollSpeed
            )
            let headPoint = point(at: 0, playbackTime: playbackTime)
            let headScale = projection.scale(at: headProgress)
            position = .zero
            headCap.position = headPoint
            headCap.setScale(headScale)
            band.lineWidth = laneWidth * 0.45 * headScale
            completedBand.lineWidth = band.lineWidth
            remainingBand.lineWidth = band.lineWidth
            core.lineWidth = 2 * headScale
            completedCore.lineWidth = core.lineWidth
            remainingCore.lineWidth = core.lineWidth

            if state == .active {
                cropMask.position.y = headPoint.y
                glowPulseRemaining = max(glowPulseRemaining - delta, 0)
                let pulse = CGFloat(glowPulseRemaining / 0.12)
                crest.alpha = 0.78 + 0.22 * min(pulse, 1)
                crest.setScale(headScale * (1 + 0.12 * min(pulse, 1)))
            } else {
                cropMask.position.y = 0
                crest.alpha = 1
                crest.setScale(headScale)
            }

            if state == .pending, playbackTime > note.time + 0.150 {
                markInactive()
            }

            let tailPoint = point(at: note.duration, playbackTime: playbackTime)
            let visibilityPadding = capHeight * headScale * 0.5
            let visible = max(headPoint.y, tailPoint.y) >= -visibilityPadding
                && min(headPoint.y, tailPoint.y) <= sceneHeight + visibilityPadding
            isHidden = state == .finished || !visible
            if !isHidden {
                applyPaths(at: playbackTime)
            }

            guard state == .active, fingerOn, playbackTime < note.time + note.duration else {
                crest.isHidden = true
                return
            }

            crest.isHidden = false
            crest.position = point(
                at: max(playbackTime - note.time, 0),
                playbackTime: playbackTime
            )
        }

        private func makeSpinePoints() -> [SpinePoint] {
            guard laneWidth > 0, scrollSpeed > 0 else { return [] }

            var points = [SpinePoint]()
            points.reserveCapacity(note.lanePath.count + 2)
            points.append(SpinePoint(offset: 0, lane: note.lane))
            for keyframe in note.lanePath where keyframe.offset > 0 && keyframe.offset < note.duration {
                points.append(SpinePoint(offset: keyframe.offset, lane: keyframe.lane))
            }
            if points.last?.offset != note.duration {
                points.append(SpinePoint(offset: note.duration, lane: lane(at: note.duration)))
            }
            return points
        }

        private func applyPaths(at playbackTime: TimeInterval) {
            band.path = steppedPath(at: playbackTime)
            core.path = band.path
            let inactive = state == .inactive
            band.strokeColor = inactive ? inactiveBandColor : bodyBandColor
            core.strokeColor = inactive ? inactiveCoreColor : bodyColor
            band.isHidden = false
            core.isHidden = false
            completedBand.isHidden = true
            completedCore.isHidden = true
            remainingBand.isHidden = true
            remainingCore.isHidden = true
            headCap.isHidden = state == .active || state == .finished
            if inactive {
                headCap.fillColor = inactiveBandColor
                headCap.strokeColor = inactiveCoreColor
            }

            guard state == .broken, let breakOffset else {
                return
            }

            band.isHidden = true
            core.isHidden = true
            completedBand.path = steppedPath(
                at: playbackTime,
                from: 0,
                through: breakOffset
            )
            completedCore.path = completedBand.path
            completedBand.strokeColor = bodyBandColor
            completedCore.strokeColor = bodyColor
            remainingBand.path = steppedPath(
                at: playbackTime,
                from: breakOffset,
                through: note.duration
            )
            remainingCore.path = remainingBand.path
            remainingBand.strokeColor = inactiveBandColor
            remainingCore.strokeColor = inactiveCoreColor
            completedBand.isHidden = false
            completedCore.isHidden = false
            remainingBand.isHidden = false
            remainingCore.isHidden = false
        }

        private func steppedPath(
            at playbackTime: TimeInterval,
            from startOffset: TimeInterval = 0,
            through endOffset: TimeInterval? = nil
        ) -> CGPath? {
            let first = point(at: startOffset, playbackTime: playbackTime)
            let path = CGMutablePath()
            path.move(to: first)
            var previous = first
            var previousOffset = startOffset

            for spinePoint in spinePoints where spinePoint.offset > startOffset {
                if let endOffset, spinePoint.offset >= endOffset {
                    break
                }

                let current = point(at: spinePoint.offset, playbackTime: playbackTime)
                path.addLine(to: CGPoint(x: previous.x, y: current.y))
                path.addLine(to: current)
                previous = current
                previousOffset = spinePoint.offset
            }

            if let endOffset, endOffset > previousOffset {
                let current = point(at: endOffset, playbackTime: playbackTime)
                path.addLine(to: CGPoint(x: previous.x, y: current.y))
                path.addLine(to: current)
            }
            return path
        }

        private func point(
            at offset: TimeInterval,
            playbackTime: TimeInterval
        ) -> CGPoint {
            guard let projection, laneWidth > 0 else { return .zero }
            let progress = projection.progress(
                timeToHit: note.time + offset - playbackTime,
                scrollSpeed: scrollSpeed
            )
            return projection.point(lane: lane(at: offset), at: progress)
        }

        private func lane(at elapsed: TimeInterval) -> Double {
            var currentLane = note.lane

            for keyframe in note.lanePath {
                let offset = max(keyframe.offset, 0)
                guard offset > 0 else {
                    currentLane = keyframe.lane
                    continue
                }

                if elapsed < offset {
                    return currentLane
                }
                currentLane = keyframe.lane
            }

            return currentLane
        }

        private func laneTolerance(at elapsed: TimeInterval) -> Double {
            guard !note.lanePath.isEmpty else { return 1.1 }

            for keyframe in note.lanePath {
                let offset = max(keyframe.offset, 0)
                guard offset > 0, offset < note.duration else { continue }
                if abs(elapsed - offset) <= 0.15 {
                    return 1.5
                }
            }

            return 1.1
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
    private let noteSpeedMultiplier: @Sendable () -> CGFloat
    private let laneCount: Int
    private let completionFallbackTime: TimeInterval

    private var noteNodes: [TapNoteNode] = []
    private var ribbonNodes: [RibbonNode] = []
    private var gradientNodes: [SKSpriteNode] = []
    private var laneFillNodes: [SKShapeNode] = []
    private var boundaryNodes: [SKShapeNode] = []
    private var receptorNodes: [SKShapeNode] = []
    private var lifeSegmentNodes: [SKShapeNode] = []
    private var receptorFlashRemaining: [TimeInterval] = []
    private var hitPopNodes: [HitPopNode] = []
    private var rippleNodes: [SKShapeNode] = []
    private var rippleStates = Array(repeating: RippleState(), count: 6)
    private let backgroundOverlayNode = SKShapeNode()
    private let scanlineOverlayNode = SKSpriteNode()
    private let hitLineNode = SKShapeNode()
    private let comboPanelOuterNode = SKShapeNode()
    private let comboPanelInnerNode = SKShapeNode()
    private let scorePanelOuterNode = SKShapeNode()
    private let scorePanelInnerNode = SKShapeNode()
    private let lifePanelOuterNode = SKShapeNode()
    private let lifePanelInnerNode = SKShapeNode()
    private let comboCaptionLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let comboValueLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private var comboOutlineLabels: [SKLabelNode] = []
    private let comboOutlineOffsets = [
        CGPoint(x: -1.5, y: 0),
        CGPoint(x: 1.5, y: 0),
        CGPoint(x: 0, y: -1.5),
        CGPoint(x: 0, y: 1.5)
    ]
    private let latestJudgmentLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let scoreCaptionLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let scoreValueLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let lifeCaptionLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let lifeGaugeTrack = SKShapeNode()
    private let lifeGaugeFill = SKShapeNode()
    private let gameOverLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var laneAreaRect = CGRect.zero
    private var laneWidth: CGFloat = 0
    private var hitLineY: CGFloat = 0
    private var perspectiveProjection: PerspectiveProjection?
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
        noteSpeedMultiplier: @escaping @Sendable () -> CGFloat = { 1 },
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
        self.noteSpeedMultiplier = noteSpeedMultiplier
        scrollSpeedMultiplier = min(max(noteSpeedMultiplier(), 0.5), 1.5)
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

        scanlineOverlayNode.texture = makeScanlineTexture()
        scanlineOverlayNode.anchorPoint = .zero
        scanlineOverlayNode.zPosition = -1
        scanlineOverlayNode.alpha = 0.045
        addChild(scanlineOverlayNode)

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
        for panel in [
            comboPanelOuterNode,
            scorePanelOuterNode,
            lifePanelOuterNode
        ] {
            panel.fillColor = makeColor(for: theme.backgroundTop, alpha: 0.35)
            panel.strokeColor = laneLineColor.withAlphaComponent(0.75)
            panel.lineWidth = 1
            panel.zPosition = 10
        }
        for panel in [
            comboPanelInnerNode,
            scorePanelInnerNode,
            lifePanelInnerNode
        ] {
            panel.fillColor = .clear
            panel.strokeColor = laneLineColor.withAlphaComponent(0.45)
            panel.lineWidth = 1
            panel.zPosition = 10.1
        }

        comboCaptionLabel.text = nil
        comboCaptionLabel.isHidden = true
        comboCaptionLabel.horizontalAlignmentMode = .center
        comboCaptionLabel.verticalAlignmentMode = .center
        comboCaptionLabel.zPosition = 12

        comboValueLabel.text = "0"
        comboValueLabel.fontSize = 36
        comboValueLabel.fontColor = .white
        comboValueLabel.horizontalAlignmentMode = .center
        comboValueLabel.verticalAlignmentMode = .center
        comboValueLabel.zPosition = 12

        for offset in comboOutlineOffsets {
            let outline = SKLabelNode(fontNamed: "Menlo-Bold")
            outline.text = "0"
            outline.fontSize = 36
            outline.fontColor = .black.withAlphaComponent(0.85)
            outline.horizontalAlignmentMode = .center
            outline.verticalAlignmentMode = .center
            outline.position = offset
            outline.zPosition = 11.9
            comboOutlineLabels.append(outline)
            addChild(outline)
        }

        latestJudgmentLabel.fontSize = 22
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
        scoreValueLabel.fontSize = 18
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

        lifeGaugeFill.fillColor = .clear
        lifeGaugeFill.strokeColor = .clear
        lifeGaugeFill.zPosition = 13

        for _ in 0..<20 {
            let segment = SKShapeNode()
            segment.fillColor = lifeGaugeColor(for: 1)
            segment.strokeColor = .clear
            segment.zPosition = 13.1
            lifeSegmentNodes.append(segment)
            addChild(segment)
        }

        gameOverLabel.text = "게임 오버"
        gameOverLabel.fontSize = 38
        gameOverLabel.fontColor = judgmentAccentColor
        gameOverLabel.horizontalAlignmentMode = .center
        gameOverLabel.verticalAlignmentMode = .center
        gameOverLabel.zPosition = 14
        gameOverLabel.isHidden = true

        addChild(comboPanelOuterNode)
        addChild(comboPanelInnerNode)
        addChild(scorePanelOuterNode)
        addChild(scorePanelInnerNode)
        addChild(lifePanelOuterNode)
        addChild(lifePanelInnerNode)
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
        guard !hasCompleted, !isPaused else { return }

        refreshNoteSpeedMultiplier()

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

        if let perspectiveProjection {
            for node in noteNodes {
                node.update(
                    playbackTime: time,
                    projection: perspectiveProjection,
                    scrollSpeed: currentScrollSpeed,
                    sceneHeight: size.height
                )
            }
        }
        for node in ribbonNodes {
            node.update(
                playbackTime: time,
                delta: delta
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
                ribbon.markActivated(at: time)
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

    var effectiveScrollSpeed: CGFloat {
        currentScrollSpeed
    }

    private func refreshNoteSpeedMultiplier() {
        let multiplier = min(max(noteSpeedMultiplier(), 0.5), 1.5)
        guard abs(multiplier - scrollSpeedMultiplier) > 0.000_001 else { return }

        scrollSpeedMultiplier = multiplier
        guard let perspectiveProjection, laneWidth > 0 else { return }
        for node in ribbonNodes {
            node.updateLayout(
                projection: perspectiveProjection,
                scrollSpeed: currentScrollSpeed,
                sceneHeight: size.height
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
        scanlineOverlayNode.size = size
        scanlineOverlayNode.position = .zero

        laneAreaRect = GameplayLayout.laneAreaRect(in: size)
        let usableWidth = laneAreaRect.width
        laneWidth = usableWidth / CGFloat(laneCount)
        hitLineY = GameplayLayout.hitLineY(in: size)
        let projection = PerspectiveProjection(
            centerX: laneAreaRect.midX,
            topY: size.height,
            hitLineY: hitLineY,
            bottomLaneWidth: laneWidth,
            laneCount: laneCount
        )
        perspectiveProjection = projection
        let laneFillColor = makeColor(for: theme.laneFill)
        for (index, lane) in laneFillNodes.enumerated() {
            let path = CGMutablePath()
            path.move(to: CGPoint(
                x: projection.laneBoundaryX(index, at: 0),
                y: projection.y(at: 0)
            ))
            path.addLine(to: CGPoint(
                x: projection.laneBoundaryX(index + 1, at: 0),
                y: projection.y(at: 0)
            ))
            path.addLine(to: CGPoint(
                x: projection.laneBoundaryX(index + 1, at: 1),
                y: projection.y(at: 1)
            ))
            path.addLine(to: CGPoint(
                x: projection.laneBoundaryX(index, at: 1),
                y: projection.y(at: 1)
            ))
            path.closeSubpath()
            lane.path = path
            lane.fillColor = laneFillColor
            lane.alpha = index.isMultiple(of: 2)
                ? CGFloat(theme.laneFillAlpha)
                : CGFloat(theme.laneFillAlpha * 0.6)
        }

        let hitLinePath = CGMutablePath()
        hitLinePath.move(to: CGPoint(x: laneAreaRect.minX, y: hitLineY))
        hitLinePath.addLine(to: CGPoint(x: laneAreaRect.maxX, y: hitLineY))
        hitLineNode.path = hitLinePath

        for (index, boundary) in boundaryNodes.enumerated() {
            let path = CGMutablePath()
            path.move(to: CGPoint(
                x: projection.laneBoundaryX(index, at: 0),
                y: projection.y(at: 0)
            ))
            path.addLine(to: CGPoint(
                x: projection.laneBoundaryX(index, at: 1),
                y: projection.y(at: 1)
            ))
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
            receptor.lineWidth = 2
            receptor.glowWidth = 0
            receptor.alpha = 1
        }

        let rippleCenter = CGPoint(x: laneAreaRect.midX, y: size.height * 0.22)
        for ripple in rippleNodes {
            ripple.position = rippleCenter
        }

        let hudTopMargin = max(size.height * 0.06, 54)
        comboValueLabel.position = CGPoint(x: laneAreaRect.midX, y: size.height - hudTopMargin - 48)
        for (index, outline) in comboOutlineLabels.enumerated() {
            let offset = comboOutlineOffsets[index]
            outline.position = CGPoint(
                x: comboValueLabel.position.x + offset.x,
                y: comboValueLabel.position.y + offset.y
            )
        }
        latestJudgmentLabel.position = CGPoint(x: laneAreaRect.midX, y: size.height - hudTopMargin)
        let scoreCenterX = laneAreaRect.maxX + (size.width - laneAreaRect.maxX) / 2
        scoreCaptionLabel.position = CGPoint(x: scoreCenterX, y: size.height * 0.10 + 16)
        scoreValueLabel.position = CGPoint(x: scoreCenterX, y: size.height * 0.10 - 10)

        let lifeCenterX = laneAreaRect.minX / 2
        let gaugeHeight = min(max(size.height * 0.60, 120), size.height * 0.75)
        let gaugeBottom = max((size.height - gaugeHeight) / 2, 8)
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

        let segmentGap: CGFloat = 3
        let segmentHeight = max((gaugeHeight - segmentGap * 19) / 20, 1)
        let segmentPath = CGPath(
            roundedRect: CGRect(x: -8, y: 0, width: 16, height: segmentHeight),
            cornerWidth: 4,
            cornerHeight: 4,
            transform: nil
        )
        for (index, segment) in lifeSegmentNodes.enumerated() {
            segment.path = segmentPath
            segment.position = CGPoint(
                x: lifeCenterX,
                y: gaugeBottom + CGFloat(index) * (segmentHeight + segmentGap)
            )
        }

        let gutterWidth = min(laneAreaRect.minX, size.width - laneAreaRect.maxX)
        let gutterPanelWidth = max(min(gutterWidth - 12, 180), 104)
        updatePanel(
            outer: scorePanelOuterNode,
            inner: scorePanelInnerNode,
            rect: CGRect(
                x: scoreCenterX - gutterPanelWidth / 2,
                y: max(size.height * 0.03, 8),
                width: gutterPanelWidth,
                height: 80
            )
        )
        updatePanel(
            outer: lifePanelOuterNode,
            inner: lifePanelInnerNode,
            rect: CGRect(
                x: lifeCenterX - gutterPanelWidth / 2,
                y: max(gaugeBottom - 24, 8),
                width: gutterPanelWidth,
                height: gaugeHeight + 60
            )
        )
        updatePanel(
            outer: comboPanelOuterNode,
            inner: comboPanelInnerNode,
            rect: CGRect(
                x: laneAreaRect.midX - 100,
                y: max(size.height - hudTopMargin - 84, 8),
                width: 200,
                height: 100
            )
        )

        for node in noteNodes {
            node.updateLayout(laneWidth: laneWidth)
        }
        for node in ribbonNodes {
            node.updateLayout(
                projection: projection,
                scrollSpeed: currentScrollSpeed,
                sceneHeight: size.height
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

    private func updatePanel(
        outer: SKShapeNode,
        inner: SKShapeNode,
        rect: CGRect
    ) {
        outer.path = CGPath(
            roundedRect: rect,
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        )
        inner.path = CGPath(
            roundedRect: rect.insetBy(dx: 5, dy: 5),
            cornerWidth: 5,
            cornerHeight: 5,
            transform: nil
        )
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
                receptor.glowWidth = 0
                receptor.alpha = 1
            } else {
                receptor.strokeColor = judgmentAccentColor
                receptor.glowWidth = 4
                receptor.alpha = CGFloat(0.45 + 0.55 * (remaining / 0.18))
            }
        }
    }

    private func flashReceptor(_ lane: Int) {
        guard receptorNodes.indices.contains(lane) else { return }
        receptorFlashRemaining[lane] = 0.18
        receptorNodes[lane].strokeColor = judgmentAccentColor
        receptorNodes[lane].glowWidth = 4
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
            judgmentText = "PERFECT"
            onHaptic(.perfect)
        case .great:
            judgmentText = "GREAT"
            onHaptic(.light)
        case .good:
            judgmentText = "GOOD"
            onHaptic(.light)
        case .bad:
            judgmentText = "BAD"
            onHaptic(.light)
        case .miss:
            judgmentText = "MISS"
        }

        latestJudgmentLabel.text = judgmentText
        latestJudgmentLabel.fontColor = judgmentColor(for: result.judgment)
        latestJudgmentLabel.alpha = 1
        latestJudgmentTime = time
        comboPulseRemaining = 0.18
        comboValueLabel.setScale(1.12)
        for outline in comboOutlineLabels {
            outline.setScale(1.12)
        }
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
            for outline in comboOutlineLabels {
                outline.text = "\(combo)"
            }
            lastRenderedCombo = combo
        }

        let score = judgmentEngine.score
        if score != lastRenderedScore {
            scoreValueLabel.text = String(format: "%07d", score)
            lastRenderedScore = score
        }

        let life = judgmentEngine.life
        if life <= 0 {
            lifeGaugeFill.yScale = 0
            lifeGaugeFill.isHidden = true
            for segment in lifeSegmentNodes {
                segment.isHidden = true
            }
            lastRenderedLife = life
        } else if life != lastRenderedLife {
            let fraction = CGFloat(life) / 100
            lifeGaugeFill.xScale = 1
            lifeGaugeFill.yScale = 1
            lifeGaugeFill.isHidden = false
            let filledSegmentCount = min(max(life / 5, 0), lifeSegmentNodes.count)
            let color = lifeGaugeColor(for: fraction)
            for (index, segment) in lifeSegmentNodes.enumerated() {
                segment.fillColor = color
                segment.isHidden = index >= filledSegmentCount
            }
            lastRenderedLife = life
        }

        comboPulseRemaining = max(comboPulseRemaining - lastFrameDelta, 0)
        let pulse = comboPulseRemaining / 0.18
        let scale = 1 + 0.12 * CGFloat(pulse)
        comboValueLabel.setScale(scale)
        for outline in comboOutlineLabels {
            outline.setScale(scale)
        }
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

    private func judgmentColor(for judgment: Judgment) -> SKColor {
        switch judgment {
        case .perfect:
            return .cyan
        case .great:
            return .green
        case .good:
            return .yellow
        case .bad:
            return .orange
        case .miss:
            return .red
        }
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
