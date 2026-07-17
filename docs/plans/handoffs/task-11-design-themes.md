# Codex Handoff — Task 11: Design theme presets + note/lane redesign

Read `AGENTS.md` first. Owner feedback after playtest: gameplay works, but the
visualizer, notes, drag ribbons, and background all share near-identical colors
(everything blends together), tap notes should be rounded rectangles (not
circles), drag notes should be straight (not curved) with tap-note-shaped
head/tail caps, and the 4 lanes must be clearly visible.

This REPLACES the old "droplet + undulating ribbon" visual identity. Keep the
one signature element: the contracting timing guide (now a rounded-rect
outline). All existing 34 tests must stay green; gameplay/judgment logic is
untouched — this is rendering + theming only.

## 1. Theme system

Create `AutoWave/Core/Models/GameTheme.swift` — a value type with named preset
themes and a deterministic selector:

```swift
struct GameTheme: Codable, Sendable, Equatable {
    var id: String                    // preset key
    var displayName: String           // Korean
    var backgroundTop: RGB            // simple Codable RGB struct (r,g,b 0…1)
    var backgroundBottom: RGB
    var laneFill: RGB;    var laneFillAlpha: Double
    var laneLine: RGB;    var laneLineAlpha: Double
    var tapNote: RGB                  // fill
    var tapNoteStroke: RGB
    var dragBody: RGB                 // ribbon body (translucent, alpha in scene)
    var dragCap: RGB                  // head/tail caps
    var ripple: RGB                   // background visualizer ripples
    var judgmentAccent: RGB           // PERFECT flash / combo text
    static func select(tempo: Double, meanBass: Float, meanMid: Float, meanTreble: Float, meanRMS: Float) -> GameTheme
    static let presets: [GameTheme]
}
```

Five presets (exact values; note hues deliberately ≥60° from background hues —
that separation is the point of this task):

| id | 이름 | bgTop → bgBottom | tapNote / stroke | dragBody / dragCap | ripple | accent | lane line |
|---|---|---|---|---|---|---|---|
| deepSea | 심해 | #070B26 → #17103F | #4FC3F7 / #FFFFFF | #7E57C2 / #B39DDB | #283593 | #FFD54F | #7986CB |
| neonRush | 네온 러시 | #16001F → #300046 | #FF4081 / #FFFFFF | #00E5FF / #84FFFF | #6A1B9A | #FFFF00 | #E040FB |
| tide | 파도 | #03242C → #0A4A55 | #FFB74D / #FFF3E0 | #26C6DA / #B2EBF2 | #00695C | #FFE082 | #4DD0E1 |
| dawn | 새벽 | #191223 → #38284C | #FFCA7A / #FFF8E1 | #F48FB1 / #FCE4EC | #5E35B1 | #80DEEA | #CE93D8 |
| prism | 백광 | #0F1216 → #1B222E | #E8F6FF / #90CAF9 | #80DEEA / #E0F7FA | #37474F | #FFAB91 | #B0BEC5 |

Selection rule (deterministic): dominant band = max(meanBass, meanMid,
meanTreble). bass-dominant → tempo ≥ 130 ? neonRush : deepSea. mid-dominant →
tide. treble-dominant → dawn. If the top two bands differ by <10% relative →
prism. (Keep `ThemePalette` for stored beatmaps' backward compat: derive it
from the selected theme's tapNote color; BeatmapGenerator now ALSO stores the
selected theme id — add `themeID: String` to `Beatmap` with a decode default of
"deepSea" so existing saved beatmaps still decode.)

Wire selection into `BeatmapGenerator.generate` (it has the analysis values).
Bump `BeatmapGenerator.version` to 2. Update generator tests for the new field
(decode-default test for old JSON without themeID).

## 2. Note redesign (GameScene)

- **Tap note**: rounded rectangle, width = laneWidth × 0.62, height 22 pt,
  corner radius 8. Fill `tapNote`, 2 pt stroke `tapNoteStroke`. Timing guide =
  a larger concentric rounded-rect outline that contracts and coincides with
  the note's edge exactly at hit time (same mechanic as before, new shape).
  Hit effect: outline flash + small particle burst in `judgmentAccent`.
- **Drag note**: STRAIGHT segments only — vertical body; moving drags render as
  straight polyline segments between lanePath keyframes (no bezier/sine
  undulation — delete the wave-offset path code). Body = rounded-rect strip,
  width = laneWidth × 0.45, color `dragBody` alpha 0.5 with a solid 2 pt core
  line; **head cap and tail cap are exact copies of the tap-note rounded rect**
  (same size/fill/stroke) so players read "press here, release here". Crest
  glow while held = brightened body segment near current time. Broken state:
  grey desaturation as today.
- **Lanes**: make the 4 columns obvious — per-lane background fill `laneFill`
  at `laneFillAlpha` (alternate ×0.6 alpha on odd lanes for contrast), 1 pt
  vertical separator lines `laneLine` at `laneLineAlpha` on all 5 boundaries,
  and at the hit line draw 4 per-lane receptor slots: rounded-rect outlines
  matching the tap-note footprint in `laneLine` color that flash `judgmentAccent`
  when a note is hit in that lane.
- Background gradient `backgroundTop→backgroundBottom` (SKSpriteNode with
  shader or layered nodes), ripples use `ripple` color — visually distinct from
  note colors by construction. Wash-in animation keeps working with the theme's
  background colors.
- GameScene reads all colors from the beatmap's `GameTheme` (look up preset by
  `themeID`; fallback deepSea). Remove now-dead palette-derived color code
  paths in the scene (LibraryView/AnalysisView accents may keep using
  ThemePalette).

## 3. Verification

- `xcodegen generate` if files added.
- All existing tests green + new/updated generator tests (theme selection
  determinism: fixed analysis fixture → expected preset id per rule; old-JSON
  decode default).
- Typecheck only in your sandbox; orchestrator runs the simulator gate and eyes
  the result. Do NOT alter judgment/scoring/clock logic. Scene callback code
  must stay main-actor-free (see the PlaybackClock pattern) and allocation-free
  in per-frame paths (pool the receptor flash nodes).
