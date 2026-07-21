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

private func blend(_ first: RGB, _ second: RGB, amount: Double) -> RGB {
    let progress = min(max(amount, 0), 1)
    return RGB(
        r: first.r + (second.r - first.r) * progress,
        g: first.g + (second.g - first.g) * progress,
        b: first.b + (second.b - first.b) * progress
    )
}

final class GameScene: SKScene, @unchecked Sendable {
    private static let neonSkyMid = RGB(hex: 0x171044)

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

        static let noteHeight: CGFloat = 22
        static let texturePadding: CGFloat = 8

        private let body = SKSpriteNode()

        var isConsumed = false

        init(note: Note) {
            self.note = note
            super.init()

            addChild(body)
            zPosition = 3
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateLayout(laneWidth: CGFloat, texture: SKTexture) {
            let noteWidth = laneWidth * 0.62
            body.texture = texture
            body.texture?.filteringMode = .linear
            body.size = CGSize(
                width: noteWidth + Self.texturePadding * 2,
                height: Self.noteHeight + Self.texturePadding * 2
            )
        }

        static func makeTexture(fillColor: SKColor, noteSize: CGSize) -> SKTexture {
            let canvasSize = CGSize(
                width: noteSize.width + texturePadding * 2,
                height: noteSize.height + texturePadding * 2
            )
            let format = UIGraphicsImageRendererFormat()
            format.opaque = false
            format.scale = 3

            let image = UIGraphicsImageRenderer(size: canvasSize, format: format).image { rendererContext in
                let context = rendererContext.cgContext
                let pillRect = CGRect(
                    x: texturePadding,
                    y: texturePadding,
                    width: noteSize.width,
                    height: noteSize.height
                )
                let pillPath = UIBezierPath(
                    roundedRect: pillRect,
                    cornerRadius: noteSize.height / 2
                )
                let colors = colorComponents(from: fillColor)

                context.saveGState()
                context.setShadow(
                    offset: .zero,
                    blur: 8,
                    color: fillColor.cgColor
                )
                context.setFillColor(fillColor.cgColor)
                context.addPath(pillPath.cgPath)
                context.fillPath()
                context.restoreGState()

                let bodyGradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [
                        shade(colors, by: 0.55).cgColor,
                        fillColor.cgColor,
                        shade(colors, by: -0.42).cgColor
                    ] as CFArray,
                    locations: [0, 0.5, 1]
                )!
                context.saveGState()
                context.addPath(pillPath.cgPath)
                context.clip()
                context.drawLinearGradient(
                    bodyGradient,
                    start: CGPoint(x: pillRect.midX, y: pillRect.minY),
                    end: CGPoint(x: pillRect.midX, y: pillRect.maxY),
                    options: []
                )
                context.restoreGState()

                let highlightHeight = noteSize.height * 0.30
                let highlightInset = noteSize.width * 0.13
                let highlightRect = CGRect(
                    x: pillRect.minX + highlightInset,
                    y: pillRect.minY + noteSize.height * 0.12,
                    width: noteSize.width - highlightInset * 2,
                    height: highlightHeight
                )
                let highlightPath = UIBezierPath(
                    roundedRect: highlightRect,
                    cornerRadius: highlightHeight / 2
                )
                let highlightGradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [
                        UIColor.white.withAlphaComponent(0.55).cgColor,
                        UIColor.white.withAlphaComponent(0).cgColor
                    ] as CFArray,
                    locations: [0, 1]
                )!
                context.saveGState()
                context.addPath(highlightPath.cgPath)
                context.clip()
                context.drawLinearGradient(
                    highlightGradient,
                    start: CGPoint(x: highlightRect.midX, y: highlightRect.minY),
                    end: CGPoint(x: highlightRect.midX, y: highlightRect.maxY),
                    options: []
                )
                context.restoreGState()

                let dashHeight = max(noteSize.height * 0.14, 3)
                let dashRect = CGRect(
                    x: pillRect.midX - noteSize.width * 0.25,
                    y: pillRect.midY - dashHeight / 2,
                    width: noteSize.width * 0.50,
                    height: dashHeight
                )
                let dashPath = UIBezierPath(
                    roundedRect: dashRect,
                    cornerRadius: dashHeight / 2
                )
                context.saveGState()
                context.setShadow(
                    offset: .zero,
                    blur: 8,
                    color: UIColor.white.withAlphaComponent(0.85).cgColor
                )
                context.setFillColor(UIColor.white.cgColor)
                context.addPath(dashPath.cgPath)
                context.fillPath()
                context.restoreGState()

                context.setStrokeColor(UIColor.white.withAlphaComponent(0.75).cgColor)
                context.setLineWidth(1.5)
                context.addPath(pillPath.cgPath)
                context.strokePath()
            }
            return SKTexture(image: image)
        }

        private static func colorComponents(from color: SKColor) -> (CGFloat, CGFloat, CGFloat) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
                return (1, 1, 1)
            }
            return (red, green, blue)
        }

        private static func shade(
            _ components: (CGFloat, CGFloat, CGFloat),
            by amount: CGFloat
        ) -> UIColor {
            if amount >= 0 {
                return UIColor(
                    red: components.0 + (1 - components.0) * amount,
                    green: components.1 + (1 - components.1) * amount,
                    blue: components.2 + (1 - components.2) * amount,
                    alpha: 1
                )
            }

            let scale = 1 + amount
            return UIColor(
                red: components.0 * scale,
                green: components.1 * scale,
                blue: components.2 * scale,
                alpha: 1
            )
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
            guard progress >= 0 else {
                isHidden = true
                return
            }
            let point = projection.point(lane: note.lane, at: progress)
            let scale = projection.scale(at: progress)

            guard !isConsumed, playbackTime <= note.time + 0.170 else {
                isHidden = true
                return
            }

            let halfNoteHeight = Self.noteHeight * scale * 0.5
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
        private let headDash = SKShapeNode()
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
            headCap.glowWidth = 6
            headCap.zPosition = 2
            headDash.fillColor = .white
            headDash.strokeColor = .clear
            headDash.blendMode = .add
            headDash.zPosition = 1
            headCap.addChild(headDash)

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
            return timeOffset <= 0.170
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
            headDash.path = CGPath(
                roundedRect: CGRect(
                    x: -capWidth * 0.25,
                    y: -1.5,
                    width: capWidth * 0.50,
                    height: 3
                ),
                cornerWidth: 1.5,
                cornerHeight: 1.5,
                transform: nil
            )
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
            guard headProgress >= 0 else {
                isHidden = true
                return
            }
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

            if state == .pending, playbackTime > note.time + 0.170 {
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

    private final class LaneHitEffectNode: SKNode {
        private static let beamStripCount = 10

        private let lane: Int
        private let contentNode = SKNode()
        private let contentCropNode = SKCropNode()
        private let contentMaskNode = SKShapeNode()
        private let beamCropNode = SKCropNode()
        private let beamMaskNode = SKShapeNode()
        private let beamContainer = SKNode()
        private let beamStrips: [SKShapeNode]
        private let burstNode = SKNode()
        private let burstOuter = SKShapeNode(circleOfRadius: 1)
        private let burstMid = SKShapeNode(circleOfRadius: 0.62)
        private let burstCore = SKShapeNode(circleOfRadius: 0.16)
        private let ring = SKShapeNode(circleOfRadius: 1)
        private var color: SKColor
        private var laneWidth: CGFloat = 0

        init(lane: Int, color: SKColor) {
            self.lane = lane
            self.color = color
            beamStrips = (0..<Self.beamStripCount).map { _ in SKShapeNode() }
            super.init()

            beamMaskNode.fillColor = .white
            beamMaskNode.strokeColor = .clear
            beamCropNode.maskNode = beamMaskNode
            beamCropNode.addChild(beamContainer)
            contentNode.addChild(beamCropNode)

            contentMaskNode.fillColor = .white
            contentMaskNode.strokeColor = .clear
            contentCropNode.maskNode = contentMaskNode
            contentCropNode.addChild(contentNode)

            for strip in beamStrips {
                strip.strokeColor = .clear
                strip.blendMode = .add
                beamContainer.addChild(strip)
            }

            burstOuter.strokeColor = .clear
            burstMid.strokeColor = .clear
            burstCore.strokeColor = .clear
            for burst in [burstOuter, burstMid, burstCore] {
                burst.blendMode = .add
                burstNode.addChild(burst)
            }
            contentNode.addChild(burstNode)

            ring.fillColor = .clear
            ring.lineWidth = 2.5
            ring.blendMode = .add
            contentNode.addChild(ring)
            addChild(contentCropNode)

            zPosition = 4
            isHidden = true
            updateColors(color)
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateLayout(projection: PerspectiveProjection) {
            position = projection.point(lane: Double(lane), at: 1)
            laneWidth = projection.laneWidth(at: 1)

            let topY = projection.y(at: 0) - position.y
            let topLeftX = projection.laneBoundaryX(lane, at: 0) - position.x
            let topRightX = projection.laneBoundaryX(lane + 1, at: 0) - position.x
            let bottomLeftX = projection.laneBoundaryX(lane, at: 1) - position.x
            let bottomRightX = projection.laneBoundaryX(lane + 1, at: 1) - position.x
            let maskPath = CGMutablePath()
            maskPath.move(to: CGPoint(x: topLeftX, y: topY))
            maskPath.addLine(to: CGPoint(x: topRightX, y: topY))
            maskPath.addLine(to: CGPoint(x: bottomRightX, y: 0))
            maskPath.addLine(to: CGPoint(x: bottomLeftX, y: 0))
            maskPath.closeSubpath()
            beamMaskNode.path = maskPath
            contentMaskNode.path = maskPath

            let beamHeight = projection.travelHeight * 0.42
            let stripWidth = laneWidth
            for index in beamStrips.indices {
                let lower = beamHeight * CGFloat(index) / CGFloat(Self.beamStripCount)
                let upper = beamHeight * CGFloat(index + 1) / CGFloat(Self.beamStripCount)
                beamStrips[index].path = CGPath(
                    rect: CGRect(
                        x: -stripWidth / 2,
                        y: lower,
                        width: stripWidth,
                        height: upper - lower + 0.5
                    ),
                    transform: nil
                )
            }
            updateColors(color)
        }

        func trigger(at point: CGPoint, color: SKColor) {
            self.color = color
            updateColors(color)
            position = point
            isHidden = false
            contentNode.removeAllActions()
            burstNode.removeAllActions()
            ring.removeAllActions()
            contentNode.alpha = 1
            burstNode.setScale(laneWidth * 0.15)
            ring.setScale(laneWidth * 0.15)

            let duration: TimeInterval = 0.25
            let fade = SKAction.fadeAlpha(to: 0, duration: duration)
            fade.timingMode = .linear
            let burstExpansion = SKAction.scale(to: laneWidth * 0.44, duration: duration)
            burstExpansion.timingMode = .linear
            let ringExpansion = SKAction.scale(to: laneWidth * 0.42, duration: duration)
            ringExpansion.timingMode = .linear
            contentNode.run(fade)
            burstNode.run(burstExpansion)
            ring.run(ringExpansion)
        }

        private func updateColors(_ color: SKColor) {
            for index in beamStrips.indices {
                let progress = CGFloat(index) / CGFloat(Self.beamStripCount - 1)
                if progress < 0.25 {
                    let alpha = 0.92 - progress * 1.2
                    beamStrips[index].fillColor = SKColor.white.withAlphaComponent(alpha)
                } else {
                    let alpha = 0.28 * (1 - progress) / 0.75
                    beamStrips[index].fillColor = color.withAlphaComponent(alpha)
                }
            }

            burstOuter.fillColor = color.withAlphaComponent(0.08)
            burstMid.fillColor = color.withAlphaComponent(0.38)
            burstCore.fillColor = SKColor.white.withAlphaComponent(0.94)
            ring.strokeColor = color
        }
    }

    private final class RingGaugeNode: SKNode {
        private static let segmentCount = 28
        private static let startAngle = CGFloat.pi * 0.75
        private static let cyan = SKColor(red: 56 / 255, green: 189 / 255, blue: 248 / 255, alpha: 1)
        private static let blue = SKColor(red: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 1)
        private static let purple = SKColor(red: 168 / 255, green: 85 / 255, blue: 247 / 255, alpha: 1)
        private static let pink = SKColor(red: 240 / 255, green: 171 / 255, blue: 252 / 255, alpha: 1)

        private let maxSweepFraction: CGFloat
        private let track = SKShapeNode()
        private let core = SKShapeNode(circleOfRadius: 1)
        private let segments: [SKShapeNode]
        private var radius: CGFloat = 0

        init(maxSweepFraction: CGFloat) {
            self.maxSweepFraction = maxSweepFraction
            segments = (0..<Self.segmentCount).map { _ in SKShapeNode() }
            super.init()

            track.fillColor = .clear
            track.strokeColor = SKColor.white.withAlphaComponent(0.12)
            track.zPosition = 0
            addChild(track)

            core.fillColor = SKColor.black.withAlphaComponent(0.72)
            core.strokeColor = .clear
            core.zPosition = 1
            addChild(core)

            for segment in segments {
                segment.fillColor = .clear
                segment.lineWidth = 7
                segment.lineCap = .round
                segment.zPosition = 2
                addChild(segment)
            }

            zPosition = 10
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateLayout(diameter: CGFloat, coreColor: SKColor) {
            radius = max(diameter / 2 - 5, 1)
            track.path = arcPath(radius: radius, start: Self.startAngle, sweep: 2 * .pi)
            track.lineWidth = 7
            core.fillColor = coreColor
            core.setScale(max(diameter / 2 - 14, 1))
            update(progress: 1, warning: false)
        }

        func update(progress: CGFloat, warning: Bool) {
            guard radius > 0 else { return }

            let sweep = 2 * CGFloat.pi * maxSweepFraction
            let progress = min(max(progress, 0), 1)
            let segmentSweep = sweep / CGFloat(Self.segmentCount)
            let visibleSweep = sweep * progress
            for index in segments.indices {
                let start = CGFloat(index) * segmentSweep
                let segmentProgress = min(max((visibleSweep - start) / segmentSweep, 0), 1)
                segments[index].isHidden = segmentProgress <= 0.001
                segments[index].path = arcPath(
                    radius: radius,
                    start: Self.startAngle + start,
                    sweep: segmentSweep * segmentProgress
                )
                segments[index].strokeColor = warning
                    ? warningColor(at: CGFloat(index) / CGFloat(max(Self.segmentCount - 1, 1)))
                    : gradientColor(at: CGFloat(index) / CGFloat(max(Self.segmentCount - 1, 1)))
            }
        }

        private func arcPath(radius: CGFloat, start: CGFloat, sweep: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.addArc(
                center: .zero,
                radius: radius,
                startAngle: start,
                endAngle: start + max(sweep, 0.0001),
                clockwise: false
            )
            return path
        }

        private func gradientColor(at progress: CGFloat) -> SKColor {
            let amount = min(max(progress, 0), 1)
            if amount < 0.38 {
                return interpolate(Self.cyan, Self.blue, amount / 0.38)
            }
            if amount < 0.84 {
                return interpolate(Self.blue, Self.purple, (amount - 0.38) / 0.46)
            }
            return interpolate(Self.purple, Self.pink, (amount - 0.84) / 0.16)
        }

        private func warningColor(at progress: CGFloat) -> SKColor {
            interpolate(
                SKColor(red: 249 / 255, green: 115 / 255, blue: 22 / 255, alpha: 1),
                SKColor(red: 239 / 255, green: 68 / 255, blue: 68 / 255, alpha: 1),
                progress
            )
        }

        private func interpolate(_ first: SKColor, _ second: SKColor, _ progress: CGFloat) -> SKColor {
            var firstRed: CGFloat = 0
            var firstGreen: CGFloat = 0
            var firstBlue: CGFloat = 0
            var firstAlpha: CGFloat = 0
            var secondRed: CGFloat = 0
            var secondGreen: CGFloat = 0
            var secondBlue: CGFloat = 0
            var secondAlpha: CGFloat = 0
            guard first.getRed(&firstRed, green: &firstGreen, blue: &firstBlue, alpha: &firstAlpha),
                  second.getRed(&secondRed, green: &secondGreen, blue: &secondBlue, alpha: &secondAlpha) else {
                return first
            }

            let amount = min(max(progress, 0), 1)
            return SKColor(
                red: firstRed + (secondRed - firstRed) * amount,
                green: firstGreen + (secondGreen - firstGreen) * amount,
                blue: firstBlue + (secondBlue - firstBlue) * amount,
                alpha: firstAlpha + (secondAlpha - firstAlpha) * amount
            )
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
    private let laneEdgeAColor: SKColor
    private let laneEdgeBColor: SKColor
    private let rippleColor: SKColor
    private let judgmentAccentColor: SKColor
    private let scrollSpeed: CGFloat
    private let noteSpeedState: NoteSpeedMultiplierState
    private let laneCount: Int
    private let completionFallbackTime: TimeInterval
    private let tapNoteTextureCache = NSCache<NSString, SKTexture>()

    private var noteNodes: [TapNoteNode] = []
    private var ribbonNodes: [RibbonNode] = []
    private var gradientNodes: [SKSpriteNode] = []
    private var laneFillNodes: [SKShapeNode] = []
    private var lanePressNodes: [SKShapeNode] = []
    private var laneHitEffectNodes: [LaneHitEffectNode] = []
    private var boundaryNodes: [SKShapeNode] = []
    private var receptorNodes: [SKShapeNode] = []
    private var receptorGlyphNodes: [SKShapeNode] = []
    private var starNodes: [SKShapeNode] = []
    private var receptorFlashRemaining: [TimeInterval] = []
    private var rippleNodes: [SKShapeNode] = []
    private var rippleStates = Array(repeating: RippleState(), count: 6)
    private let backgroundOverlayNode = SKShapeNode()
    private let citySilhouetteNode = SKShapeNode()
    private let scanlineOverlayNode = SKSpriteNode()
    private let hitLineNode = SKShapeNode()
    private let healthRingNode = RingGaugeNode(maxSweepFraction: 0.85)
    private let scoreRingNode = RingGaugeNode(maxSweepFraction: 1)
    private let healthIconLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let healthCaptionLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let healthValueLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let scoreIconLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let latestJudgmentLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let scoreCaptionLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let scoreValueLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let scoreComboLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let gameOverLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var laneAreaRect = CGRect.zero
    private var laneWidth: CGFloat = 0
    private var hitLineY: CGFloat = 0
    private let starAnchors: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [
        (0.14, 0.84, 1.0),
        (0.24, 0.72, 0.8),
        (0.69, 0.88, 1.0),
        (0.79, 0.74, 0.8),
        (0.88, 0.55, 1.0),
        (0.08, 0.52, 0.8),
        (0.64, 0.58, 0.7)
    ]
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
        noteSpeedState: NoteSpeedMultiplierState = NoteSpeedMultiplierState(),
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
        laneEdgeAColor = makeColor(for: selectedTheme.laneEdgeA)
        laneEdgeBColor = makeColor(for: selectedTheme.laneEdgeB)
        rippleColor = makeColor(for: selectedTheme.ripple)
        judgmentAccentColor = makeColor(for: selectedTheme.judgmentAccent)
        scrollSpeed = CGFloat(DifficultyProfile.profile(for: difficulty).scrollSpeed)
        self.noteSpeedState = noteSpeedState
        scrollSpeedMultiplier = min(max(noteSpeedState.value, 0.5), 1.5)
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
        backgroundOverlayNode.zPosition = -4.75
        backgroundOverlayNode.alpha = 0
        addChild(backgroundOverlayNode)

        citySilhouetteNode.fillColor = makeColor(for: RGB(hex: 0x090822), alpha: 0.94)
        citySilhouetteNode.strokeColor = .clear
        citySilhouetteNode.zPosition = -4
        addChild(citySilhouetteNode)

        for anchor in starAnchors {
            let star = SKShapeNode(circleOfRadius: anchor.radius)
            star.fillColor = SKColor.white.withAlphaComponent(0.58)
            star.strokeColor = .clear
            star.zPosition = -4.5
            starNodes.append(star)
            addChild(star)
        }

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
        hitLineNode.strokeColor = laneLineColor.withAlphaComponent(0.38)
        hitLineNode.lineWidth = 1

        receptorFlashRemaining = Array(repeating: .zero, count: laneCount)
        for index in 0..<laneCount {
            let lane = SKShapeNode()
            lane.fillColor = makeColor(for: theme.laneFill)
            lane.strokeColor = .clear
            lane.zPosition = -3
            laneFillNodes.append(lane)
            addChild(lane)

            let press = SKShapeNode()
            press.fillColor = judgmentAccentColor
            press.strokeColor = .clear
            press.blendMode = .add
            press.zPosition = -2.5
            press.isHidden = true
            lanePressNodes.append(press)
            addChild(press)

            let hitEffect = LaneHitEffectNode(lane: laneFillNodes.count - 1, color: judgmentAccentColor)
            laneHitEffectNodes.append(hitEffect)
            addChild(hitEffect)

            let receptor = SKShapeNode()
            receptor.fillColor = makeColor(for: theme.backgroundBottom, alpha: 0.86)
            receptor.strokeColor = laneEdgeColor(forLane: index)
            receptor.lineWidth = 2
            receptor.glowWidth = 4
            receptor.zPosition = 2.5
            receptorNodes.append(receptor)
            addChild(receptor)

            let glyph = SKShapeNode()
            glyph.fillColor = .clear
            glyph.strokeColor = laneEdgeColor(forLane: index).withAlphaComponent(0.62)
            glyph.lineWidth = 1
            glyph.zPosition = 3
            receptorGlyphNodes.append(glyph)
            addChild(glyph)
        }

        for index in 0...laneCount {
            let boundary = SKShapeNode()
            boundary.strokeColor = boundaryColor(for: index)
            boundary.lineWidth = 2
            boundary.glowWidth = 5
            boundary.zPosition = 1
            boundaryNodes.append(boundary)
            addChild(boundary)
        }

        for note in beatmap.notes where note.kind == .tap {
            let node = TapNoteNode(
                note: note
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
        healthIconLabel.text = "♥"
        healthIconLabel.fontSize = 18
        healthIconLabel.fontColor = .white
        healthIconLabel.horizontalAlignmentMode = .center
        healthIconLabel.verticalAlignmentMode = .center
        healthIconLabel.zPosition = 12

        healthCaptionLabel.text = "HEALTH"
        healthCaptionLabel.fontSize = 9
        healthCaptionLabel.fontColor = SKColor.white.withAlphaComponent(0.72)
        healthCaptionLabel.horizontalAlignmentMode = .center
        healthCaptionLabel.verticalAlignmentMode = .center
        healthCaptionLabel.zPosition = 12

        healthValueLabel.text = "100%"
        healthValueLabel.fontSize = 21
        healthValueLabel.fontColor = .white
        healthValueLabel.horizontalAlignmentMode = .center
        healthValueLabel.verticalAlignmentMode = .center
        healthValueLabel.zPosition = 12

        scoreIconLabel.text = "★"
        scoreIconLabel.fontSize = 18
        scoreIconLabel.fontColor = .white
        scoreIconLabel.horizontalAlignmentMode = .center
        scoreIconLabel.verticalAlignmentMode = .center
        scoreIconLabel.zPosition = 12

        latestJudgmentLabel.fontSize = 22
        latestJudgmentLabel.fontColor = judgmentAccentColor
        latestJudgmentLabel.horizontalAlignmentMode = .center
        latestJudgmentLabel.verticalAlignmentMode = .center
        latestJudgmentLabel.alpha = 0
        latestJudgmentLabel.zPosition = 12

        scoreCaptionLabel.text = "SCORE"
        scoreCaptionLabel.fontSize = 9
        scoreCaptionLabel.fontColor = SKColor.white.withAlphaComponent(0.72)
        scoreCaptionLabel.horizontalAlignmentMode = .center
        scoreCaptionLabel.verticalAlignmentMode = .center
        scoreCaptionLabel.zPosition = 12

        scoreValueLabel.text = "0000000"
        scoreValueLabel.fontSize = 15
        scoreValueLabel.fontColor = .white
        scoreValueLabel.horizontalAlignmentMode = .center
        scoreValueLabel.verticalAlignmentMode = .center
        scoreValueLabel.zPosition = 12

        scoreComboLabel.text = "0"
        scoreComboLabel.fontSize = 18
        scoreComboLabel.fontColor = judgmentAccentColor
        scoreComboLabel.horizontalAlignmentMode = .center
        scoreComboLabel.verticalAlignmentMode = .center
        scoreComboLabel.zPosition = 12

        gameOverLabel.text = "게임 오버"
        gameOverLabel.fontSize = 38
        gameOverLabel.fontColor = judgmentAccentColor
        gameOverLabel.horizontalAlignmentMode = .center
        gameOverLabel.verticalAlignmentMode = .center
        gameOverLabel.zPosition = 14
        gameOverLabel.isHidden = true

        addChild(healthRingNode)
        addChild(scoreRingNode)
        addChild(healthIconLabel)
        addChild(healthCaptionLabel)
        addChild(healthValueLabel)
        addChild(scoreIconLabel)
        addChild(latestJudgmentLabel)
        addChild(scoreCaptionLabel)
        addChild(scoreValueLabel)
        addChild(scoreComboLabel)
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
            let touchLaneIndex = laneIndex(for: touchLane)
            flashLane(touchLaneIndex)

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
                    showHitEffect(at: lane, judgment: result.judgment)
                }
                continue
            }

            let lane = touchLaneIndex

            guard let result = judgmentEngine.tap(lane: lane, at: time) else { continue }

            consumeNearestVisual(lane: lane, at: time)
            showJudgment(result, at: CACurrentMediaTime())
            if result.judgment != .miss {
                flashReceptor(lane)
                showHitEffect(at: lane, judgment: result.judgment)
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
        let multiplier = min(max(noteSpeedState.value, 0.5), 1.5)
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
        updateBackgroundLayout()
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
            lane.fillColor = makeColor(for: laneFillColor(for: index))
            lane.alpha = index.isMultiple(of: 2)
                ? CGFloat(theme.laneFillAlpha)
                : CGFloat(theme.laneFillAlpha * 0.75)
            lanePressNodes[index].path = path
            lanePressNodes[index].fillColor = judgmentAccentColor
            laneHitEffectNodes[index].updateLayout(projection: projection)
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
            boundary.strokeColor = boundaryColor(for: index)
            boundary.lineWidth = 2
            boundary.glowWidth = 5
            boundary.alpha = CGFloat(theme.laneLineAlpha)
        }

        let receptorRect = CGRect(
            x: -laneWidth * 0.31,
            y: -14,
            width: laneWidth * 0.62,
            height: 28
        )
        let receptorPath = CGPath(
            roundedRect: receptorRect,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        let glyphSize = min(max(laneWidth * 0.08, 5), 8)
        let glyphPath = CGMutablePath()
        glyphPath.move(to: CGPoint(x: 0, y: glyphSize))
        glyphPath.addLine(to: CGPoint(x: glyphSize, y: 0))
        glyphPath.addLine(to: CGPoint(x: 0, y: -glyphSize))
        glyphPath.addLine(to: CGPoint(x: -glyphSize, y: 0))
        glyphPath.closeSubpath()
        for (index, receptor) in receptorNodes.enumerated() {
            receptor.path = receptorPath
            receptor.position = CGPoint(
                x: laneAreaRect.minX + (CGFloat(index) + 0.5) * laneWidth,
                y: hitLineY
            )
            receptor.fillColor = makeColor(for: theme.backgroundBottom, alpha: 0.86)
            receptor.strokeColor = laneEdgeColor(forLane: index)
            receptor.lineWidth = 2
            receptor.glowWidth = 4
            receptor.alpha = 1
            receptorGlyphNodes[index].path = glyphPath
            receptorGlyphNodes[index].position = receptor.position
            receptorGlyphNodes[index].strokeColor = laneEdgeColor(forLane: index).withAlphaComponent(0.62)
        }

        let rippleCenter = CGPoint(x: laneAreaRect.midX, y: size.height * 0.22)
        for ripple in rippleNodes {
            ripple.position = rippleCenter
        }

        let gutterWidth = min(laneAreaRect.minX, size.width - laneAreaRect.maxX)
        let gaugeDiameter = min(max(gutterWidth - 12, 105), 128)
        let gaugeY = size.height * 0.50
        let healthCenterX = laneAreaRect.minX / 2
        let scoreCenterX = laneAreaRect.maxX + (size.width - laneAreaRect.maxX) / 2
        let healthCenter = CGPoint(x: healthCenterX, y: gaugeY)
        let scoreCenter = CGPoint(x: scoreCenterX, y: gaugeY)
        let gaugeCoreColor = makeColor(for: theme.backgroundBottom, alpha: 0.94)
        healthRingNode.position = healthCenter
        scoreRingNode.position = scoreCenter
        healthRingNode.updateLayout(diameter: gaugeDiameter, coreColor: gaugeCoreColor)
        scoreRingNode.updateLayout(diameter: gaugeDiameter, coreColor: gaugeCoreColor)

        healthIconLabel.position = CGPoint(x: healthCenterX, y: gaugeY + gaugeDiameter * 0.19)
        healthCaptionLabel.position = CGPoint(x: healthCenterX, y: gaugeY + gaugeDiameter * 0.03)
        healthValueLabel.position = CGPoint(x: healthCenterX, y: gaugeY - gaugeDiameter * 0.18)
        scoreIconLabel.position = CGPoint(x: scoreCenterX, y: gaugeY + gaugeDiameter * 0.20)
        scoreCaptionLabel.position = CGPoint(x: scoreCenterX, y: gaugeY + gaugeDiameter * 0.04)
        scoreValueLabel.position = CGPoint(x: scoreCenterX, y: gaugeY - gaugeDiameter * 0.08)
        scoreComboLabel.position = CGPoint(x: scoreCenterX, y: gaugeY - gaugeDiameter * 0.29)
        latestJudgmentLabel.position = CGPoint(x: laneAreaRect.midX, y: size.height - max(size.height * 0.06, 54))
        gameOverLabel.position = CGPoint(x: laneAreaRect.midX, y: size.height * 0.52)

        for node in noteNodes {
            node.updateLayout(
                laneWidth: laneWidth,
                texture: tapNoteTexture(for: laneWidth)
            )
        }
        for node in ribbonNodes {
            node.updateLayout(
                projection: projection,
                scrollSpeed: currentScrollSpeed,
                sceneHeight: size.height
            )
        }

        lastRenderedLife = nil
        updateHUD()
    }

    private var currentScrollSpeed: CGFloat {
        scrollSpeed * scrollSpeedMultiplier
    }

    private func tapNoteTexture(for laneWidth: CGFloat) -> SKTexture {
        let noteWidth = laneWidth * 0.62
        let widthClass = max(Int((noteWidth * 2).rounded()), 1)
        let key = "tapNote:\(widthClass)" as NSString
        if let texture = tapNoteTextureCache.object(forKey: key) {
            return texture
        }

        let texture = TapNoteNode.makeTexture(
            fillColor: tapNoteColor,
            noteSize: CGSize(
                width: CGFloat(widthClass) / 2,
                height: TapNoteNode.noteHeight
            )
        )
        tapNoteTextureCache.setObject(texture, forKey: key)
        return texture
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
                receptor.strokeColor = laneEdgeColor(forLane: index)
                receptor.glowWidth = 4
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

    private func laneFillColor(for lane: Int) -> RGB {
        let edge = lane.isMultiple(of: 2) ? theme.laneEdgeA : theme.laneEdgeB
        return blend(theme.laneFill, edge, amount: 0.24)
    }

    private func laneEdgeColor(forLane lane: Int) -> SKColor {
        lane.isMultiple(of: 2) ? laneEdgeAColor : laneEdgeBColor
    }

    private func boundaryColor(for index: Int) -> SKColor {
        guard index != 0, index != laneCount else {
            return laneEdgeAColor
        }
        return index.isMultiple(of: 2) ? laneEdgeAColor : laneEdgeBColor
    }

    private func updateBackgroundLayout() {
        for (index, anchor) in starAnchors.enumerated() where starNodes.indices.contains(index) {
            starNodes[index].position = CGPoint(
                x: size.width * anchor.x,
                y: size.height * anchor.y
            )
        }

        let baseY = size.height * 0.25
        let heights: [CGFloat] = [
            0.08, 0.14, 0.10, 0.20, 0.12, 0.18, 0.11, 0.16,
            0.09, 0.19, 0.13, 0.17, 0.10, 0.15, 0.08, 0.12
        ]
        let buildingWidth = size.width / CGFloat(heights.count)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: baseY))
        for (index, height) in heights.enumerated() {
            let x = CGFloat(index) * buildingWidth
            let top = baseY + size.height * height
            path.addLine(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x + buildingWidth * 0.72, y: top))
            path.addLine(to: CGPoint(x: x + buildingWidth * 0.72, y: baseY))
            path.addLine(to: CGPoint(x: x + buildingWidth, y: baseY))
        }
        path.addLine(to: CGPoint(x: size.width, y: 0))
        path.closeSubpath()
        citySilhouetteNode.path = path
    }

    private func gradientColor(at progress: CGFloat) -> SKColor {
        let amount = min(max(progress, 0), 1)
        let top = theme.backgroundTop
        let mid = Self.neonSkyMid
        let bottom = theme.backgroundBottom
        let color: RGB
        if amount < 0.42 {
            color = blend(bottom, mid, amount: Double(amount / 0.42))
        } else {
            color = blend(mid, top, amount: Double((amount - 0.42) / 0.58))
        }
        return makeColor(
            for: color
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
        var nearestDistance = TimeInterval(0.170).nextUp

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
        var nearestDistance = TimeInterval(0.170).nextUp

        for node in noteNodes where !node.isConsumed && node.note.lane == Double(lane) {
            let distance = abs(node.note.time - time)
            guard distance <= 0.170, distance < nearestDistance else { continue }
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
        scoreComboLabel.setScale(1.12)
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

    private func flashLane(_ lane: Int) {
        guard lanePressNodes.indices.contains(lane) else { return }

        let node = lanePressNodes[lane]
        node.removeAllActions()
        node.isHidden = false
        node.alpha = 0.30
        let fade = SKAction.fadeAlpha(to: 0, duration: 0.18)
        fade.timingMode = .linear
        node.run(fade)
    }

    private func showHitEffect(at lane: Int, judgment: Judgment) {
        guard judgment != .miss,
              laneHitEffectNodes.indices.contains(lane) else { return }

        laneHitEffectNodes[lane].trigger(
            at: receptorPoint(for: lane),
            color: judgmentAccentColor
        )
    }

    private func updateHUD() {
        let combo = judgmentEngine.combo
        if combo != lastRenderedCombo {
            scoreComboLabel.text = "\(combo)"
            lastRenderedCombo = combo
        }

        let score = judgmentEngine.score
        if score != lastRenderedScore {
            scoreValueLabel.text = String(format: "%07d", score)
            lastRenderedScore = score
        }

        let life = judgmentEngine.life
        if life != lastRenderedLife {
            let fraction = CGFloat(max(life, 0)) / 100
            healthValueLabel.text = "\(max(life, 0))%"
            healthRingNode.update(progress: fraction, warning: life < 25)
            lastRenderedLife = life
        }

        comboPulseRemaining = max(comboPulseRemaining - lastFrameDelta, 0)
        let pulse = comboPulseRemaining / 0.18
        let scale = 1 + 0.12 * CGFloat(pulse)
        scoreComboLabel.setScale(scale)
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
