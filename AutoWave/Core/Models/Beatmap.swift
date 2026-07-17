struct Beatmap: Codable, Sendable, Equatable {
    var difficulty: Difficulty
    var tempo: Double
    var notes: [Note]
    var palette: ThemePalette
    var generatorVersion: Int
    var themeID: String

    init(
        difficulty: Difficulty,
        tempo: Double,
        notes: [Note],
        palette: ThemePalette,
        generatorVersion: Int,
        themeID: String = GameTheme.defaultID
    ) {
        self.difficulty = difficulty
        self.tempo = tempo
        self.notes = notes
        self.palette = palette
        self.generatorVersion = generatorVersion
        self.themeID = themeID
    }

    private enum CodingKeys: String, CodingKey {
        case difficulty
        case tempo
        case notes
        case palette
        case generatorVersion
        case themeID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        difficulty = try container.decode(Difficulty.self, forKey: .difficulty)
        tempo = try container.decode(Double.self, forKey: .tempo)
        notes = try container.decode([Note].self, forKey: .notes)
        palette = try container.decode(ThemePalette.self, forKey: .palette)
        generatorVersion = try container.decode(Int.self, forKey: .generatorVersion)
        themeID = try container.decodeIfPresent(String.self, forKey: .themeID)
            ?? GameTheme.defaultID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(tempo, forKey: .tempo)
        try container.encode(notes, forKey: .notes)
        try container.encode(palette, forKey: .palette)
        try container.encode(generatorVersion, forKey: .generatorVersion)
        try container.encode(themeID, forKey: .themeID)
    }
}
