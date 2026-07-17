# Codex Handoff — Task 13: App-wide landscape lock + block in-game back gesture + thinner hit line

Read `AGENTS.md` first. Preserve the crash-fix invariants (scene callbacks run
off the main actor; AVFoundation closures are `@Sendable`). All existing tests
stay green.

Owner requirements:
- The app must be **landscape from launch** on every screen (home, library,
  import, analysis, profile, gameplay, results) — no portrait, no rotation
  flip mid-use.
- In gameplay, the iOS **swipe-from-left-edge back gesture must not exit the
  game** (currently a left→right drag pops the view and quits mid-song).
- The gameplay hit line at the bottom is **too thick**, so notes have too
  little travel time. Make it thin.

## 1. Orientation

- `project.yml`: set `UISupportedInterfaceOrientations` to landscape only
  (`UIInterfaceOrientationLandscapeLeft`, `UIInterfaceOrientationLandscapeRight`)
  — remove portrait. Regenerate with `xcodegen generate`.
- Remove the now-unnecessary per-screen orientation flipping in
  `GameplayContainerView` (`requestOrientation(.landscape)`/`.all` and the
  `AppDelegate.orientationLock`-style plumbing if present) since the whole app
  is landscape-locked. If an app-level `supportedInterfaceOrientationsFor`
  hook exists, simplify it to always return `.landscape`.
- Verify existing SwiftUI screens (Home/Library/Import/Analysis/Profile) lay
  out acceptably in landscape (they currently assume portrait width). Minimal
  fix: wrap their content in a `ScrollView` where needed and cap content width
  (e.g. `.frame(maxWidth: 640)` centered) so nothing clips in landscape. Do
  not redesign them here — Task 17 handles the music-select redesign; just make
  them non-broken in landscape.

## 2. Block the back gesture in gameplay

- The gameplay is presented in a `NavigationStack` path from Library. Disable
  the interactive pop gesture only while the gameplay scene is presented:
  set `.navigationBarBackButtonHidden(true)` AND disable the swipe via a small
  `UIViewControllerRepresentable`/introspection helper that sets
  `navigationController?.interactivePopGestureRecognizer?.isEnabled = false`
  on appear and re-enables it on disappear. (An in-game "나가기" / pause-exit
  button remains the only way out — that already exists in the pause overlay.)
- Ensure re-enabling on disappear so Library ↔ other screens keep normal swipe
  back.

## 3. Thinner hit line

- In `GameScene`, reduce the hit-line / receptor band thickness so notes travel
  longer. Concretely: the hit line target should sit ~12% from the bottom
  (not a thick band), the line itself ≤ 3 pt, and note spawn should start from
  the very top so the on-screen travel time at each difficulty's scrollSpeed is
  maximized. Keep receptor slot outlines (Task 11) but slim them to match the
  note height, not a fat bar.

## Verification

- `xcodegen generate`; typecheck. Orchestrator runs the simulator gate +
  launches to confirm landscape-from-launch and that a left-edge swipe during
  gameplay does not exit. All existing tests green.
- No changes to scoring/generation logic in this task.
