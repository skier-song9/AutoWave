# AutoWave — Design System Rules (Figma MCP integration)

Rules doc for translating between this codebase and Figma. Generated from code
analysis 2026-07-21. Source of truth is always the Swift code cited below.

## 1. Token definitions

### App shell tokens — `AutoWave/Core/Models/AppTheme.swift`

Single `enum AppTheme` with static `Color` values (hex literals via
`Color(hex: UInt32)`). Dark-only UI (`RootView` forces `.preferredColorScheme(.dark)`).

| Token | Hex | Usage |
|---|---|---|
| `background` | `#0A0D14` | Full-screen background (`.appScreenBackground()`) |
| `panel` | `#111722` | Card fill |
| `panelSecondary` | `#171E2C` | Secondary surface |
| `line` | `#283247` | 1px card border |
| `muted` | `#8994A8` | Secondary text |
| `text` | `#EDF2FF` | Primary text |
| `accent` | `#6DDCFF` | Tint, links, active accent |
| `accentSecondary` | `#A98CFF` | Gradient partner |
| `good` | `#63E6AE` | Success |
| `danger` | `#FF7188` | Error/destructive |

`accentGradient` = linear `accent → accentSecondary`, leading → trailing.
Used on the AutoWave wordmark, big icons, "완료!" title.

### Gameplay theme tokens — `AutoWave/Core/Models/GameTheme.swift`

Five presets, auto-selected per track from audio analysis (tempo + band energy).
Each preset defines: `backgroundTop`, `backgroundBottom` (vertical gradient),
`laneFill` (alpha 0.18), `laneLine` (alpha 0.72), `tapNote`, `tapNoteStroke`,
`dragBody`, `dragCap`, `ripple`, `judgmentAccent`.

| id | 이름 | bgTop | bgBottom | laneLine | tapNote | dragBody | dragCap | accent |
|---|---|---|---|---|---|---|---|---|
| deepSea (default) | 심해 | #070B26 | #17103F | #7986CB | #4FC3F7 | #7E57C2 | #B39DDB | #FFD54F |
| neonRush | 네온 러시 | #16001F | #300046 | #E040FB | #FF4081 | #00E5FF | #84FFFF | #FFFF00 |
| tide | 파도 | #03242C | #0A4A55 | #4DD0E1 | #FFB74D | #26C6DA | #B2EBF2 | #FFE082 |
| dawn | 새벽 | #191223 | #38284C | #CE93D8 | #FFCA7A | #F48FB1 | #FCE4EC | #80DEEA |
| prism | 백광 | #0F1216 | #1B222E | #B0BEC5 | #E8F6FF | #80DEEA | #E0F7FA | #FFAB91 |

tapNoteStroke: #FFFFFF except tide #FFF3E0, dawn #FFF8E1, prism #90CAF9.

### Fixed gameplay colors — `GameScene.swift`

- Judgment text: PERFECT=cyan, GREAT=green, GOOD=yellow, BAD=orange, MISS=red
  (system SKColors).
- Life gauge: 20 segments, green→yellow→red interpolation by fraction
  (`lifeGaugeColor(for:)`, GameScene.swift:1715).
- Difficulty tints (LibraryView): 천국=cyan, 쉬움=green, 보통=blue,
  어려움=orange, 지옥=red.
- Per-track palette: HSB derived from beatmap `tapNote` (`ThemePalette`),
  used as track dot + ripple progress tint.

No token transformation system; hex → SwiftUI `Color` / `SKColor` at runtime.
Figma variables should mirror the two collections: `App/…` and `Game/<themeID>/…`.

## 2. Component library

No formal component library / storybook. Reusable pieces:

- `.panelCard(padding: 16)` — panel fill, radius 11 continuous, 1px `line`
  border, shadow black 28% r18 y8 (`AppTheme.swift:35`).
- `.appScreenBackground()` — max frame + `background` ignoring safe area.
- `RippleProgressView` (AnalysisView.swift:129) — 3 expanding stroke circles
  (easeOut 2s, 0.55s stagger) + trimmed progress ring, lineWidth 5 round cap.
- `HomeWaveGlyph` (HomeView.swift:150) — 44×44, cyan `water.waves` SF Symbol +
  same ripple animation.
- `ProfileChip` (HomeView.swift:128) — capsule, thinMaterial, 30×30 circle
  avatar with tint fill + SF Symbol.
- `TrackRow` (LibraryView.swift:215) — 12px palette dot, title `.headline`,
  duration `.caption.monospacedDigit`, difficulty badges: `.caption2`,
  padding 7×3, capsule, tint 15% fill + 40% 0.5px stroke.
- Buttons: system `.borderedProminent` / `.bordered`, `.controlSize(.large)`
  for primary actions; tint = `AppTheme.accent`.
- Screens constrain content `maxWidth: 640` (sheet: 720), centered.

## 3. Frameworks

- SwiftUI app shell (portrait screens), SpriteKit `GameScene` (landscape
  gameplay), Swift 6. SwiftData persistence. No web/CSS stack.
- Build: XcodeGen (`project.yml`) → `AutoWave.xcodeproj`; no bundler.
- No third-party UI deps (owner rule).

## 4. Assets

`AutoWave/Resources/Assets.xcassets` — only `AppIcon` + `AccentColor`.
No bitmap sprites: every game visual is generated `SKShapeNode`/`SKSpriteNode`
geometry or programmatic texture (scanline). Keep Figma output vector-only.

## 5. Icon system

SF Symbols exclusively (`Image(systemName:)`). Naming = Apple SF Symbol names.
In-use set: `water.waves`, `play.fill`, `plus.circle.fill`, `person.2.fill`,
`link.circle`, `chart.line.uptrend.xyaxis`, `ellipsis.circle`, `pause.fill`,
`speedometer`, `waveform.badge.plus`, `checkmark.circle.fill`, `trash`,
`arrow.clockwise` + avatar set (`bolt.fill`, `music.note`, `flame.fill`,
`star.fill`, `moon.stars.fill`, `pawprint.fill`, `gamecontroller.fill`).

## 6. Styling approach

- SwiftUI modifiers + shared ViewModifiers (`PanelCardModifier`); no global
  stylesheet. Typography = system Dynamic Type styles (`largeTitle.bold`,
  `headline`, `subheadline`, `caption`…), `monospacedDigit()` for numbers.
- Gameplay HUD fonts: `Menlo-Bold` (combo 36, judgment 22, score 18,
  captions 12), `AvenirNext-Bold` 38 for 게임 오버.
- Responsive: ratio-based layout in `GameplayLayout`
  (`Core/Models/GameplayRules.swift`): lane area = 70% width centered,
  hit line y = max(18% height, 72). HUD gutters host score (right) and
  life gauge (left, 16px wide, 20 segments, gap 3). Combo panel 200×100
  top-center; gutter panels width clamp 104–180.
- Gameplay scene geometry: 1/z perspective projection of 4–7 lanes; tap note =
  rounded rect, width `laneWidth×0.62`, height 22, radius 8, stroke 2; drag
  ribbon = band `laneWidth×0.45` + 2px core + cap 22 high radius 8; receptors
  mirror note shape at hit line, stroke 2.
- User-facing strings Korean-first (judgment words stay English caps).

## 7. Project structure

```
AutoWave/
  App/            AutoWaveApp, RootView (NavigationStack + dark scheme)
  Core/
    Models/       AppTheme, GameTheme, ThemePalette, Difficulty, GameplayRules…
    BeatmapKit/   pure DSP/beatmap generation (no UI)
    AudioEngine/  VisualizerTap
  Features/
    Home/         HomeView, ProfileView
    Import/       ImportView
    Analysis/     AnalysisView(+VM)
    Library/      LibraryView (+ReadySheetView)
    Gameplay/     GameplayContainerView, GameScene (SpriteKit), ResultsView
  Resources/      Assets.xcassets
```

Screen flow: Home → (플레이) Library → Ready sheet → Gameplay (landscape)
→ Results; Home → 음원 가져오기 Import → 변환 Analysis.

## Figma integration rules

1. Mirror tokens as Figma variables: collection `App` (10 colors) and
   collection `Game` with one mode per theme id (deepSea/neonRush/tide/dawn/
   prism) holding the 10 theme slots above.
2. Components to model: PanelCard, PrimaryButton/SecondaryButton (large),
   ProfileChip, TrackRow + DifficultyBadge (5 variants), RippleProgress,
   TapNote, DragRibbon, Receptor, HUD panels (combo/score/life), JudgmentLabel
   (5 variants), PauseOverlay buttons.
3. Frames: portrait screens 402×874 (iPhone 17 Pro), gameplay 874×402
   landscape.
4. New designs must reuse `AppTheme` tokens; never hardcode new hex in
   SwiftUI without adding token first. Gameplay visuals must parameterize on
   `GameTheme` slots, not literal colors.
5. Code side has no asset pipeline — export from Figma only as geometry
   specs/values, not images (except future AppIcon).
