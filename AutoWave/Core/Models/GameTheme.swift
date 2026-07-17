import Foundation

struct RGB: Codable, Sendable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.init(
            r: Double((hex >> 16) & 0xFF) / 255,
            g: Double((hex >> 8) & 0xFF) / 255,
            b: Double(hex & 0xFF) / 255
        )
    }
}

struct GameTheme: Codable, Sendable, Equatable {
    static let defaultID = "deepSea"

    var id: String
    var displayName: String
    var backgroundTop: RGB
    var backgroundBottom: RGB
    var laneFill: RGB
    var laneFillAlpha: Double
    var laneLine: RGB
    var laneLineAlpha: Double
    var tapNote: RGB
    var tapNoteStroke: RGB
    var dragBody: RGB
    var dragCap: RGB
    var ripple: RGB
    var judgmentAccent: RGB

    static let presets: [GameTheme] = [
        GameTheme(
            id: "deepSea",
            displayName: "심해",
            backgroundTop: RGB(hex: 0x070B26),
            backgroundBottom: RGB(hex: 0x17103F),
            laneFill: RGB(hex: 0x283593),
            laneFillAlpha: 0.18,
            laneLine: RGB(hex: 0x7986CB),
            laneLineAlpha: 0.72,
            tapNote: RGB(hex: 0x4FC3F7),
            tapNoteStroke: RGB(hex: 0xFFFFFF),
            dragBody: RGB(hex: 0x7E57C2),
            dragCap: RGB(hex: 0xB39DDB),
            ripple: RGB(hex: 0x283593),
            judgmentAccent: RGB(hex: 0xFFD54F)
        ),
        GameTheme(
            id: "neonRush",
            displayName: "네온 러시",
            backgroundTop: RGB(hex: 0x16001F),
            backgroundBottom: RGB(hex: 0x300046),
            laneFill: RGB(hex: 0x6A1B9A),
            laneFillAlpha: 0.18,
            laneLine: RGB(hex: 0xE040FB),
            laneLineAlpha: 0.72,
            tapNote: RGB(hex: 0xFF4081),
            tapNoteStroke: RGB(hex: 0xFFFFFF),
            dragBody: RGB(hex: 0x00E5FF),
            dragCap: RGB(hex: 0x84FFFF),
            ripple: RGB(hex: 0x6A1B9A),
            judgmentAccent: RGB(hex: 0xFFFF00)
        ),
        GameTheme(
            id: "tide",
            displayName: "파도",
            backgroundTop: RGB(hex: 0x03242C),
            backgroundBottom: RGB(hex: 0x0A4A55),
            laneFill: RGB(hex: 0x00695C),
            laneFillAlpha: 0.18,
            laneLine: RGB(hex: 0x4DD0E1),
            laneLineAlpha: 0.72,
            tapNote: RGB(hex: 0xFFB74D),
            tapNoteStroke: RGB(hex: 0xFFF3E0),
            dragBody: RGB(hex: 0x26C6DA),
            dragCap: RGB(hex: 0xB2EBF2),
            ripple: RGB(hex: 0x00695C),
            judgmentAccent: RGB(hex: 0xFFE082)
        ),
        GameTheme(
            id: "dawn",
            displayName: "새벽",
            backgroundTop: RGB(hex: 0x191223),
            backgroundBottom: RGB(hex: 0x38284C),
            laneFill: RGB(hex: 0x5E35B1),
            laneFillAlpha: 0.18,
            laneLine: RGB(hex: 0xCE93D8),
            laneLineAlpha: 0.72,
            tapNote: RGB(hex: 0xFFCA7A),
            tapNoteStroke: RGB(hex: 0xFFF8E1),
            dragBody: RGB(hex: 0xF48FB1),
            dragCap: RGB(hex: 0xFCE4EC),
            ripple: RGB(hex: 0x5E35B1),
            judgmentAccent: RGB(hex: 0x80DEEA)
        ),
        GameTheme(
            id: "prism",
            displayName: "백광",
            backgroundTop: RGB(hex: 0x0F1216),
            backgroundBottom: RGB(hex: 0x1B222E),
            laneFill: RGB(hex: 0x37474F),
            laneFillAlpha: 0.18,
            laneLine: RGB(hex: 0xB0BEC5),
            laneLineAlpha: 0.72,
            tapNote: RGB(hex: 0xE8F6FF),
            tapNoteStroke: RGB(hex: 0x90CAF9),
            dragBody: RGB(hex: 0x80DEEA),
            dragCap: RGB(hex: 0xE0F7FA),
            ripple: RGB(hex: 0x37474F),
            judgmentAccent: RGB(hex: 0xFFAB91)
        )
    ]

    static func select(
        tempo: Double,
        meanBass: Float,
        meanMid: Float,
        meanTreble: Float,
        meanRMS: Float
    ) -> GameTheme {
        _ = meanRMS

        let bands = [
            (value: Double(meanBass), order: 0),
            (value: Double(meanMid), order: 1),
            (value: Double(meanTreble), order: 2)
        ].sorted {
            if $0.value == $1.value {
                return $0.order < $1.order
            }
            return $0.value > $1.value
        }

        let dominant = bands[0]
        let runnerUp = bands[1]
        let relativeDifference = dominant.value == 0
            ? 0
            : (dominant.value - runnerUp.value) / dominant.value

        if relativeDifference < 0.10 {
            return preset(id: "prism")
        }

        switch dominant.order {
        case 0:
            return preset(id: tempo >= 130 ? "neonRush" : "deepSea")
        case 1:
            return preset(id: "tide")
        default:
            return preset(id: "dawn")
        }
    }

    static func preset(id: String) -> GameTheme {
        presets.first { $0.id == id } ?? presets[0]
    }

    var themePalette: ThemePalette {
        let maximum = max(tapNote.r, max(tapNote.g, tapNote.b))
        let minimum = min(tapNote.r, min(tapNote.g, tapNote.b))
        let range = maximum - minimum
        let hue: Double

        if range == 0 {
            hue = 0
        } else if maximum == tapNote.r {
            hue = ((tapNote.g - tapNote.b) / range / 6).normalizedHue
        } else if maximum == tapNote.g {
            hue = ((tapNote.b - tapNote.r) / range + 2) / 6
        } else {
            hue = ((tapNote.r - tapNote.g) / range + 4) / 6
        }

        return ThemePalette(
            hue: hue,
            saturation: maximum == 0 ? 0 : range / maximum,
            brightness: maximum
        )
    }
}

private extension Double {
    var normalizedHue: Double {
        self >= 0 ? self : self + 1
    }
}
