import SwiftUI

extension ThemePalette {
    var color: Color {
        Color(
            hue: hue.truncatingRemainder(dividingBy: 1).normalizedHue,
            saturation: min(max(saturation, 0), 1),
            brightness: min(max(brightness, 0), 1)
        )
    }
}

private extension Double {
    var normalizedHue: Double {
        self >= 0 ? self : self + 1
    }
}
