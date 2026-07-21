# Task 30 — Neon gameplay scene (GameScene + GameTheme + tests)

Design source of truth: `docs/design/styleguide.html` §04 "Gameplay" mock +
§03 TapNote/GemNote/Receptor/RingGauge specs (matches `refs/ref3.png`).
Depends on tasks 28–29.

## Goal

Port the SpriteKit gameplay visuals to the neon highway language: alternating
pink/cyan lane edges, rounded receptor pads, glossy notes with a white center
dash, and circular HUD ring gauges replacing the rectangular panels + 20-segment
life bar. Gameplay logic (judgment, scoring, spawning, input) must not change.

## 1. GameTheme.swift retint + new fields

- Add per-theme fields `laneEdgeA` (pink family) and `laneEdgeB` (cyan family)
  with sensible values for all 5 presets; deepSea: A #F048C6, B #38BDF8.
- Retint deepSea to the styleguide sky: backgroundTop #050617,
  backgroundBottom #08091D (mid-stop purple handled in-scene), laneFill stays
  dark translucent (keep laneFillAlpha semantics), tapNote #38BDF8,
  judgmentAccent #A855F7. Adjust the other 4 presets minimally so they stay
  distinct but harmonize with the neon direction (keep their identity hues).
- `AutoWaveTests/BeatmapGeneratorTests.swift`
  `testThemePresetsExposeExactDesignTokens` (~line 485) asserts exact hex
  values — update the expected tokens to the new values in the same structure.
  Also check `testPaletteUsesSelectedThemeTapColor` still passes.

## 2. GameScene.swift visuals (didMove-built nodes; see lines noted)

- Boundary lines (~992): alternate `laneEdgeA`/`laneEdgeB` per boundary
  (outer edges pink, inner alternating), lineWidth ~2, `glowWidth` ~4–6.
- Lane fills (~962): alternate dark translucent purple/blue tints (derive from
  edge colors at low alpha), keep laneFillAlpha contract.
- Hit line (~956): keep position; restyle subtle (low-alpha white/purple).
- Receptors (~983): rounded-rect pads (radius ~10 in scene units, existing
  receptor size contract from GameplayRules), 2pt stroke in the lane's edge
  color + glow, very dark fill, faint centered glyph (draw a small diamond
  path node; no text glyph needed). Keep press-flash behavior.
- TapNote texture (~1511): add the white horizontal center dash slot
  (rounded bar, ~50% width, ~3px at texture scale) on top of the existing
  glossy pill gradient; keep stroke/glow. Applies to drag caps too if they
  share the texture (styleguide DragRibbon caps show the dash).
- Background: vertical gradient backgroundTop→mid #171044→backgroundBottom
  (texture or layered nodes), a few faint star dots, optional simple dark
  city-silhouette strip near the horizon (skip if it risks perf).
- Judgment labels/beam/burst effects: keep, retint accents to theme
  judgmentAccent (purple).

## 3. HUD — circular ring gauges (configureHUD ~1024)

Replace comboPanel/scorePanel/lifePanel + 20-segment life gauge:

- Left gutter: HEALTH ring gauge — circular dark disc, ring stroke sweep ∝ life
  fraction (full = 360°·0.85 visual language is fine; sweep must track life),
  gradient look cyan→purple (approximate with arc segments interpolating color
  or a precomputed ring texture masked by an arc — implementer's choice),
  center: heart shape/♥ label, "HEALTH" caption, percent label (Menlo-Bold).
  Low-life warning may tint the ring toward red (keep existing danger feedback
  if present).
- Right gutter: SCORE ring — static full gradient ring, star glyph, "SCORE"
  caption, score digits (Menlo-Bold, monospaced), combo number below in purple.
  Combo count moves here; the big top-center combo panel is removed. Keep the
  judgment text (PERFECT etc.) appearing near top-center as today.
- Size: fit existing gutter width contract (GameplayRules gutter clamp);
  roughly 105–128pt diameter. Update any GameplayRules constants only if
  required, and mirror changes in GameplayRulesTests if asserted.
- Pause/speed controls (SwiftUI, task 28) unchanged.

## Constraints

- No gameplay-logic changes: JudgmentEngine, spawning, input, scoring, life
  math untouched (only their visual presentation moves).
- 60fps target: prefer textures/precomputed shapes over per-frame shape churn;
  life ring updates only on life change.
- No git. Typecheck max 1–2 xcodebuild attempts
  (`env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`). Note any
  new files for `xcodegen generate`.

## Acceptance

1. Build compiles; updated theme-token test matches new preset values; all
   other tests untouched and passing conceptually (caller runs the full suite).
2. Scene shows: pink/cyan alternating glowing lane edges, rounded receptor
   pads with glyphs, notes with white center dash, sky gradient background.
3. HUD: left health ring (sweep tracks life), right score ring with combo;
   old rectangular panels and 20-segment bar gone.
4. deepSea default matches styleguide gameplay mock palette.
