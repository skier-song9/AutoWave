# Codex Handoff — Task 21: In-game UI fixes + note speed multiplier + retro pass

Read `AGENTS.md` first. Same concurrency/alloc invariants. Owner device-test
feedback; references #12–#15 (retro handheld rhythm game: pixel-ish HUD frames,
chunky odometer score, bold outlined combo text, vertical life bar with
segment ticks) — reinterpret retro, don't clone assets.

## 1. Lane field = 70% of screen width (owner item 1)

`laneAreaRect` must span 70% of scene width, centered; gutters get HUD. Update
receptor/lane/touch mapping accordingly (touch outside lane area is ignored —
Task 19 item 7 already does this; keep consistent).

## 2. Un-overlap combo and score (owner item 3)

Combo (+ latest judgment) stays center-top; move the score readout to the
RIGHT gutter as a chunky 7-digit zero-padded odometer ("0004War120" style →
`String(format: "%07d", score)`), retro monospaced look (SKLabelNode with
Menlo/Courier bold or custom kerning). No overlap at any lane count.

## 3. Life gauge (owner item 4 + retro)

Left gutter, vertical, full height ~60%: segmented tick bar (like reference
life meters) — draw ~20 tick segments, filled count = life/5, green→amber→red
gradient by remaining life. Starts full (Task 19 fixes the fraction bug; here
just ensure the segmented rendering reads life=100 as all ticks lit).

## 4. Note fall-speed multiplier button (NEW feature, owner spec)

- Cycle button in the top-right HUD near pause: `x0.5 → x0.75 → x1.0 → x1.5 →
  x0.5 …`, label shows current multiplier ("배속 x1.0" or "x1.0").
- Multiplier scales ONLY the visual scroll speed (`scrollSpeed *
  multiplier`) — audio playback rate and judgment timing are untouched.
- The value is a USER-level persistent setting applied to every song/play:
  store `noteSpeedMultiplier: Double` on `ProfileEntity` (default 1.0, decode
  default for existing rows), read it in GameplayViewModel/GameScene at start,
  and update live when the button cycles (persist immediately via the model
  context on the MainActor hop).
- Changing speed mid-song re-lays-out falling notes on the next frame (they
  reposition by the new speed; judgment times unchanged).
- Add a ProfileEntity test for the new field's default + persistence.

## 5. Pause must work (owner items 5/6)

Owner reports the pause button does nothing now. Diagnose: likely the button's
touch is consumed by the scene's lane mapping or the SwiftUI overlay z-order
changed. Ensure: pause button hit-test wins over lane touches (exclude its
frame from lane mapping OR host pause/speed buttons in the SwiftUI layer above
SpriteView, which is simpler and keeps scene touches clean — prefer SwiftUI
buttons in the gutters), pause overlay (계속하기/다시하기/나가기 + 3-2-1
countdown resume) appears and functions as it did before the redesign.

## 6. Auto-pause on background (owner item 7)

Re-verify the `scenePhase` observer path still pauses when the app resigns
active / backgrounds, and that audio interruption (call) pauses too. The
observer exists in GameplayContainerView — trace why it stopped working after
the redesign (state enum changes?) and fix. On return, the pause overlay must
be showing (no auto-resume).

## 7. Retro visual pass (owner item 9, refs #12–#15)

Within our theme system (GameTheme colors stay the source of truth):
- HUD frames: give score/life/combo areas thin double-border "panel" frames
  (SKShapeNode strokes) like handheld UIs.
- Combo: bold outlined text (fontNamed "Menlo-Bold" or "Courier-Bold"),
  count in large digits with a small "COMBO" caption, brief scale-pop on
  increment (existing pulse ok).
- Judgment text: chunky uppercase with per-judgment color (퍼펙트 cyan,
  그레이트 green, 굿 yellow, 배드 orange, 미스 red) — keep Korean labels.
- Receptors: slightly thicker outlines with a subtle inner glow flash on hit.
- Background: keep theme gradient + ripples; add a faint horizontal scanline
  overlay (single tiled texture generated once — no per-frame work) for the
  retro CRT feel, alpha ≤ 0.06.

## Verification

`xcodegen generate` if needed. Orchestrator runs build+tests only (owner
verifies on device — no code review), so self-check your diff. All tests incl.
GameplayStartRegressionTests green; add the ProfileEntity speed-field test.
Korean UI strings.
