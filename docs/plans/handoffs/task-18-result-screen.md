# Codex Handoff — Task 18: Result screen (reference #8) + grade

Read `AGENTS.md` first. Depends on Task 14 (`JudgmentCounts` now has
perfect/great/good/bad/miss; engine exposes score, maxCombo, life/isGameOver)
and Task 16 (`GameplaySummary` gains a `failed` flag). Reference #8 is a retro
RESULT screen — REINTERPRET into our style, keep the information layout.

## Scope

Redesign `AutoWave/Features/Gameplay/ResultsView.swift` (landscape). Show:
- Title "결과" / RESULT with the track title.
- **Judgment breakdown table** (like #8): PERFECT / GREAT / GOOD / BAD / MISS
  counts, then **TOTAL** = sum of all judged notes. Use the Korean labels
  퍼펙트/그레이트/굿/배드/미스 (keep an EN sublabel if it fits the retro feel).
- **SCORE** (final total score, prominent).
- **MAX COMBO**.
- **GRADE** badge (S/A/B/C/D/F) computed from accuracy — see below.
- If the run ended by life reaching 0 (`summary.failed == true`), show a
  clear **FAILED / 실패** state (e.g. red grade F or a "STAGE FAILED" banner)
  instead of a normal grade.
- Buttons: "다시하기" (restart same track+difficulty) and "음원 선택"
  (back to the music-select screen). Keep existing restart/dismiss wiring.

## Grade

Create `AutoWave/Features/Gameplay/ScoreGrade.swift`:

```swift
enum ScoreGrade: String { case s = "S", a = "A", b = "B", c = "C", d = "D", f = "F"
    static func grade(counts: JudgmentCounts, failed: Bool) -> ScoreGrade
}
```

Rule (deterministic, testable): if `failed` ⇒ `.f`. Otherwise compute accuracy
= weighted judged points / max possible, where weight per note uses the base
points (perfect 5, great 3, good 2, bad 1, miss 0) and max possible = totalNotes
× 5. Grade thresholds on accuracy ratio: ≥0.95 S, ≥0.88 A, ≥0.78 B, ≥0.65 C,
≥0.50 D, else F. (totalNotes = sum of all counts; if 0 ⇒ F.)

## Persistence check

Results already save a `ScoreRecord` in the gameplay completion path (Task 7).
Ensure the saved record reflects the FINAL score/maxCombo from the engine
(including a failed run — a failed run still records its score). No schema
change needed unless you want to store the grade; if you do, add an optional
field with a decode default.

## Tests

`AutoWaveTests/ScoreGradeTests.swift`: failed ⇒ F; all-perfect ⇒ S; a mixed
count at a known ratio lands in the expected band at each threshold boundary;
zero notes ⇒ F.

## Verification

- `xcodegen generate` if files added. Landscape, Korean strings. Typecheck;
  orchestrator runs the gate + screenshots the result screen for a normal and a
  failed run. All existing tests green.
