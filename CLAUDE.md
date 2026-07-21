# AutoWave — CLAUDE.md

iOS rhythm game that auto-generates playable beatmaps from user-provided audio.
Landscape gameplay: notes fall from the top of the screen and are tapped/dragged in
time with the music. See `docs/plans/` for the current implementation plan.

## Collaboration model (Claude ↔ subagents)

Roles are fixed for this project:

- **Claude (main thread)**: planning, architecture, task breakdown, prompt
  writing, diff review, build verification, git commits.
- **Subagents (Agent tool)**: all feature code writing. One task per subagent;
  parallel subagents only on disjoint file sets.

Handoff protocol:

1. Claude writes a self-contained prompt per task: goal, exact file paths,
   acceptance criteria, constraints from this file.
2. The subagent implements in the working tree; it does not commit and does not
   run xcodebuild (Claude runs the single build gate to avoid concurrent builds).
3. Claude reviews `git diff`, runs the build gate and tests, fixes or
   re-dispatches as needed, then commits.

(Historical: earlier tasks were implemented via the Codex CLI
`codex:codex-rescue` handoff flow; that flow is retired.)

## Build & verification

`xcode-select` points at CommandLineTools on this machine and sudo is unavailable —
always prefix Xcode tooling with `DEVELOPER_DIR`:

```bash
# Regenerate the Xcode project after adding/removing files
xcodegen generate

# Build gate (must pass before any commit)
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project AutoWave.xcodeproj -scheme AutoWave \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Unit tests
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project AutoWave.xcodeproj -scheme AutoWave \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

- Toolchain: Xcode 26.6, Swift 6.x, XcodeGen 2.46.0 (installed via Homebrew).
- The project is defined in `project.yml`; `AutoWave.xcodeproj` is generated but
  **committed** so the owner can open it in Xcode without extra steps.
- After any file add/remove/rename: run `xcodegen generate` before building.

## Project conventions

- Swift 6, SwiftUI app shell, SpriteKit for the gameplay scene. No third-party
  dependencies without explicit owner approval.
- Persistence: SwiftData. Audio: AVFoundation/AVAudioEngine. DSP: Accelerate/vDSP.
- Beatmap generation is pure, deterministic, and unit-testable (`BeatmapKit`).
- Five difficulties, in this exact order and naming:
  천국 (Heaven), 쉬움 (Easy), 보통 (Normal), 어려움 (Hard), 지옥 (Hell).
- `refs/` is gitignored reference material — never commit it, never delete it.
- User-facing strings are Korean-first.
- YouTube audio extraction is **out of scope** (App Store rule 5.2.3 + YouTube ToS);
  input is local audio files only. Do not re-add YouTube ingestion without owner
  approval.

## Git

- Commit messages: Conventional Commits, English, subject ≤ 50 chars.
- Claude commits; Codex never runs git.
- Do not push without an explicit owner request.
