# Codex Handoff — Task 10: Polish pass

Read `AGENTS.md` and the Task 10 section of `docs/plans/2026-07-17-autowave-mvp.md`
first. Final MVP task — read all merged sources before coding; this task
touches many files lightly. No new architecture.

## Deliverables

1. **Haptics**: `UIImpactFeedbackGenerator` on judgments — perfect = rigid
   medium, great/good = light, miss = none; drag break = notification
   (.warning) generator. One prepared generator per type in the gameplay
   layer; prepare() on scene start.
2. **Pause/resume**: pause button in gameplay (top-right; also auto-pause on
   `scenePhase != .active` / audio interruption). Pause = stop playback +
   freeze scene. Overlay: "일시정지" with buttons "계속하기" / "다시하기" /
   "나가기". Resume = 3-2-1 countdown (Korean numerals fine as digits) sync'd
   before playback restarts at the exact paused position.
3. **Difficulty picker styling**: the picker sheet from Library gets per-
   difficulty tint + Korean name + short tagline: 천국 "숨쉬듯 편안하게",
   쉬움 "가볍게 몸풀기", 보통 "리듬을 타보자", 어려움 "손가락 준비운동 필수",
   지옥 "건투를 빈다". Tints: heaven soft sky, easy green, normal blue,
   hard orange, hell red (system colors fine).
4. **Empty library onboarding**: when no tracks, show a friendly empty state
   with a wave glyph (SF Symbol `water.waves`), copy "음원을 가져와서 나만의
   리듬게임을 만들어보세요", and a prominent "음원 가져오기" button.
5. **App icon**: generate a simple flat icon programmatically-designed asset —
   dark navy background, three concentric cyan ripple rings offset low-center,
   one amber droplet dot. Produce the required 1024×1024 PNG into
   `AppIcon.appiconset` (write it with a small Swift/Python script run once;
   commit the PNG; delete the script or put it under `scripts/`).
6. **Sweep**: fix any compiler warnings introduced by Tasks 1–9; ensure all
   user-facing strings are Korean; verify orientation lock still holds after
   pause/resume; ResultsView shows judgment counts with Korean labels
   (퍼펙트/그레이트/굿/미스).

## Verification

- `xcodegen generate`; full test suite must pass:
  `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AutoWave.xcodeproj -scheme AutoWave -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
- Orchestrator does the final manual run-through: Library → Import →
  Analysis → difficulty picker → Gameplay (tap + drag + pause/resume) →
  Results → back to Library.

## Constraints

- No third-party deps. No git. No new screens beyond the overlay/empty state.
- Keep haptic and pause logic out of `BeatmapKit`/`Core` value types.
