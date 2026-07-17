# Codex Handoff — Task 17: Music select screen (reference #5)

Read `AGENTS.md` first. Depends on Task 14 (ScoreRecord already exists;
gameplay saves score/maxCombo/difficulty). App is landscape-locked (Task 13).
Reference #5 is a retro music-select layout — REINTERPRET into our style, keep
the information architecture: a scrollable track list on one side, and the
SELECTED track's record/details on the other (best score, difficulty, stars/
grade, note count / BPM).

## Scope

Redesign the existing `AutoWave/Features/Library/LibraryView.swift` into a
landscape two-pane "음원 선택" screen (rename user-facing title to "음원 선택";
keep the file/type or split into a `MusicSelectView` — your call, but keep the
navigation entry from Home's "플레이" working).

Layout (landscape):
- **Left pane**: scrollable list of imported tracks (SwiftData `@Query`), each
  row shows title + duration; selection highlight. Keep swipe/context delete
  (remove entity + audio file). An "음원 가져오기" affordance remains reachable
  (toolbar or a row).
- **Right pane** (details for the selected track):
  - Track title, duration, BPM (`Beatmap.tempo`, read from any stored beatmap).
  - Per-difficulty rows for all five (천국/쉬움/보통/어려움/지옥) with the
    Korean name, a colored difficulty tint, and — if a `ScoreRecord` exists for
    that track+difficulty — the **best score**, **max combo**, and a **grade**
    (reuse the grade helper from Task 18; if that isn't merged yet, compute a
    simple grade from best score relative to a per-map max, or show "—").
    Difficulties with no beatmap yet show "변환 필요"; tapping a converted
    difficulty starts gameplay (existing navigation to
    `GameplayContainerView(track:difficulty:)`); tapping an unconverted track
    routes to Analysis as today.
  - A small "최고 기록" summary (best overall score across difficulties).
- Empty state (no tracks): keep the water.waves onboarding, adapted to
  landscape, with the "음원 가져오기" button.

## Data

- Best score per (track, difficulty): query `ScoreRecord` filtered by track and
  difficulty raw value, max by `score`. Extract a small helper
  `bestRecord(for:difficulty:in:)` and unit-test it.
- Grade: use `ScoreGrade.grade(...)` from Task 18 if available; otherwise a
  local placeholder that Task 18 can later unify (leave a TODO note, don't
  duplicate a diverging grade scale).

## Tests

`AutoWaveTests/MusicSelectTests.swift` (or extend an existing test file): the
best-record helper returns the highest-scoring record for a track+difficulty
from an in-memory container with several records, and nil when none.

## Verification

- `xcodegen generate` if files added. Landscape layout must not clip on iPhone
  17 Pro landscape. Korean strings. Typecheck; orchestrator runs the gate +
  screenshots the screen. All existing tests green; existing gameplay/analysis
  navigation must keep working.
