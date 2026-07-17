# Codex Handoff — Task 14: New scoring, combo, and life system

Read `AGENTS.md` first. This overhauls `JudgmentEngine` scoring/combo/life and
the judgment tier set. Pure logic — TDD, write/extend tests FIRST in
`AutoWaveTests/JudgmentEngineTests.swift`. Do NOT change timing-window sizes or
the drag lane-tolerance mechanics except where noted. Read the current
`AutoWave/Features/Gameplay/JudgmentEngine.swift` fully before editing.

## Judgment tiers (add `bad`)

`enum Judgment { case perfect, great, good, bad, miss }`. Timing windows
(|offset| from note time), inclusive at each boundary with the existing epsilon,
narrowest wins:
- perfect ≤ 0.045 s
- great ≤ 0.080 s
- good ≤ 0.115 s
- bad ≤ 0.150 s
- beyond 0.150 s unconsumed ⇒ miss (via `advance(to:)`)

A tap consumes the nearest unconsumed tap note in-lane within ≤0.150 s (bad
window). Update `nearestUnconsumedNoteIndex` / `judgment(for:)` accordingly.

`JudgmentCounts` gains `var bad = 0`.

## Base points

perfect 5, great 3, good 2, bad 1, miss 0.

## Combo rule (changed)

Combo counts CONSECUTIVE great-or-better. So:
- perfect or great ⇒ `combo += 1`, `maxCombo = max(...)`.
- good, bad, miss ⇒ `combo = 0` (combo breaks — good now breaks combo).

## Score with combo bonus

Per hit: `score += basePoints(judgment) + comboBonus` where `comboBonus` is the
NEW combo value on great+ hits (i.e. add the current combo count as bonus), and
`0` on good/bad/miss.
- perfect/great: `score += base + combo` (combo already incremented this hit).
- good: `score += 2`. bad: `score += 1`. miss: `score += 0`.
Examples to encode as tests: three consecutive perfects ⇒
(5+1) + (5+2) + (5+3) = 6+7+8 = 21. A great after two perfects (combo→3) ⇒
+ (3+3)=6. A good resets combo to 0 and adds 2.

## Life system

- `private(set) var life = 100` (Int), max 100, min 0.
- Each miss (including a drag that times out at the head, and a drag break):
  `life = max(0, life - 5)`.
- Life regen from score: every time cumulative `score` crosses a multiple of
  200, `life = min(100, life + 1)`. Track this by counting how many 200-point
  thresholds total score has passed since last check and adding that many
  (capped at 100). Implement so multiple thresholds crossed in one large award
  each grant +1 (still capped at 100).
- `private(set) var isGameOver = false`. When `life` reaches 0, set
  `isGameOver = true`. Expose it so the scene can end the run immediately
  (Task 16 wires "life 0 ⇒ fail, stop song, go to results"). The engine itself
  does not stop anything; it just flips the flag and keeps returning results
  safely if called again.

## Drag ticks

Keep drag-tick scoring but align with the new model: a successful tick is
great-tier equivalent — `combo += 1`, `score += 1 + combo` (a small per-tick
base of 1 plus combo bonus; tune base to 1 so long holds don't dwarf taps).
Drag break ⇒ `combo = 0`, `judgmentCounts.miss += 1`, `life -= 5`, same as a
miss. Head-timeout miss ⇒ same miss handling (life −5).

## Tests (write/extend first)

Cover: five-tier window classification incl. `bad` at exactly 0.150 and miss at
0.151; combo breaks on good (not just miss); combo bonus arithmetic (the 21 and
6 examples above); life −5 per miss; life regen +1 per 200 score with 100 cap;
multiple thresholds in one award; `isGameOver` true exactly when life hits 0
and never goes negative; drag break applies life penalty and miss count. Keep
all previously-passing drag/tap tests updated to the new numbers (recompute
expected scores — do not weaken intent).

## Verification

- Typecheck only in your sandbox; orchestrator runs the simulator gate. All
  other tests in the suite must still pass (some in other files assert old
  score numbers via gameplay — if any fail on the orchestrator side they'll be
  reported back; within this task, only `JudgmentEngineTests` should need
  number updates).
