# Codex Handoff — Task 25: Pre-game READY screen + library delete/retry

Read `AGENTS.md` first. Owner reference #16 (READY sheet before a song:
difficulty + LINE count + SPEED, then START). Orchestrator does NOT
code-review — self-check. Korean UI strings (screen title "준비" ok; keep
"START"-style action as "시작").

## 1. Persist analysis for fast regeneration

Currently changing lane count would require full re-analysis. Add persistence:
- `TrackEntity` gains `analysisData: Data?` (optional, decode-safe default
  nil): JSON-encoded `AnalysisResult` (make it Codable — it's a value type;
  onsets array included; use sortedKeys encoder).
- `AnalysisViewModel` stores it after analysis; regeneration paths reuse the
  stored analysis instead of re-analyzing when present (fall back to
  re-analysis when nil).

## 2. READY screen (replaces direct difficulty→gameplay jump)

Flow: music select → difficulty picker (existing) → **READY sheet** → 시작 →
gameplay.
- Shows: track title, chosen difficulty (changeable via segmented control of
  the 5 Korean names), **LINE (레인 수)** stepper/cycle 4·5·6·7 (default =
  difficulty's default laneCount), **SPEED (배속)** cycle x0.5/x0.75/x1.0/
  x1.5 (same persistent ProfileEntity value as the in-game button — one
  source of truth), and a prominent "시작" button. No long/slide note
  settings.
- On 시작: if the stored beatmap for (difficulty) has a different laneCount
  than chosen OR generatorVersion < current, REGENERATE that difficulty from
  the persisted analysis (fast) with `laneCount` override, show a brief
  progress state, then enter gameplay. Generator API: add an optional
  `laneCountOverride: Int?` parameter to `BeatmapGenerator.generate` (nil =
  difficulty default; override clamps 4...7). Overridden maps are stored per
  (difficulty) as today (replace).
- The chosen LINE value persists per-user on ProfileEntity
  (`preferredLaneCount: Int?`, nil = difficulty default; decode default nil)
  and pre-fills next time.

## 3. Library: delete + retry conversion (owner request)

In the library/music-select list:
- Swipe-to-delete on a track row must remove the SwiftData entities AND the
  audio file on disk (verify the existing delete path still works after the
  redesigns — repair if lost).
- Add a context menu (long-press) and/or row buttons with: "다시 변환"
  (deletes stored beatmaps + analysisData, navigates to AnalysisView to
  re-run full analysis) and "삭제" (same as swipe delete, with a
  confirmation dialog "정말 삭제할까요?").

## 4. Tests

- AnalysisResult JSON round-trip test.
- Regeneration decision: stored laneCount ≠ chosen ⇒ regenerate; equal and
  version current ⇒ no regenerate (unit-test the pure decision function).
- laneCountOverride: generate with override 6 on heaven ⇒ all lanes within
  0..<6, Beatmap.laneCount == 6; determinism holds.
- ProfileEntity new fields default/persist test.
- Retry-conversion helper: after invoking the reset function, track has no
  beatmaps and no analysisData (in-memory container).

## Verification

`xcodegen generate` if needed. Typecheck; one xcodebuild attempt max. All
existing tests stay green.
