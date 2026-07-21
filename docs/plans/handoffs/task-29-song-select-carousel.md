# Task 29 — SongSelect carousel (Home + Library merge)

Design source of truth: `docs/design/styleguide.html` §04 "SongSelect" mock
(matches `refs/ref1.png`). Depends on task 28 tokens/components.

## Goal

Replace the Home → Library two-step flow with a single landscape SongSelect
screen: a vertical carousel of circular album discs over a concentric-ring
space background. This becomes the root screen.

## Structure

- `AutoWave/Features/Home/SongSelectView.swift` (new file — mention it so the
  caller runs `xcodegen generate`):
  - Background: AppTheme.background + 3–4 concentric stroked circles
    (blue/purple ~12–22% opacity) centered on the focused disc + faint
    horizontal waveform tick bands left/right (Canvas or simple shapes).
  - Center: vertical carousel of the SwiftData tracks (same query LibraryView
    uses). Focused disc large (~55–60% of height): circular clipped album
    placeholder (gradient from track palette color), 3pt gradient ring +
    outer glow, inside bottom: title (bold), artist/duration (muted),
    small equalizer icon + top difficulty label, 5 pagination dots.
  - Neighbors above/below: smaller discs (~55% of focused), thin white ring,
    title + subtitle, partially faded. Vertical swipe / drag switches tracks;
    ‹ › chevron buttons (or up/down tap zones) also switch. Any reasonable
    carousel implementation is fine (ScrollView + scrollTargetBehavior(.paging)
    or manual offset animation) as long as swiping feels continuous.
  - Top-left: PlayerBadge (avatar circle w/ gradient ring + "PLAYER 01"-style
    chip using existing profile nickname; tap → existing ProfileView).
  - Top-right: plus CircleIconButton → ImportView (keeps existing import flow).
  - Tap on the focused disc → present the ReadyModal (task 28) for that track,
    identical onStart flow into GameplayContainerView.
  - Empty state (no tracks): centered dashed import card ("음원 파일 선택" →
    ImportView), same neon language.

## Wiring

- RootView: NavigationStack { SongSelectView() } — drop the HomeView root and
  the ellipsis debug menu, keep `.preferredColorScheme(.dark)`, tint accentPurple.
- Keep LibraryView.swift compiling (ReadySheetView lives there) but it no longer
  needs to be reachable from navigation. Keep HomeView file if removal is risky;
  otherwise delete HomeView + note the deletion. Preserve ProfileView access via
  PlayerBadge. Latest-score info from HomeView may be dropped (ref has none).
- Difficulty label on the focused disc: highest available difficulty of that
  track's beatmaps (e.g. "HARD"), colored by its tint; hide if none.

## Constraints

- Do not touch GameScene.swift/GameTheme.swift/BeatmapKit/tests.
- SwiftData queries reuse existing entities (TrackEntity etc.) — no schema changes.
- No third-party deps. No git. Typecheck max 1–2 xcodebuild attempts
  (`env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).

## Acceptance

1. Root screen is the SongSelect carousel; swiping changes focused track;
   tapping focused disc opens ReadyModal; START still launches gameplay.
2. Import reachable via plus button; profile via PlayerBadge; empty state works.
3. Matches styleguide SongSelect mock: rings background, glowing focused disc,
   clipped neighbors, chevrons, top-corner controls.
