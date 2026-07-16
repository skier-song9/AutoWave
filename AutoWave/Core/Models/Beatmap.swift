struct Beatmap: Codable, Sendable, Equatable {
    var difficulty: Difficulty
    var tempo: Double
    var notes: [Note]
    var palette: ThemePalette
    var generatorVersion: Int
}
