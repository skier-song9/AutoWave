# Task 28 — Neon shell tokens, difficulty remap, ReadyModal, screen restyle

Design source of truth: `docs/design/styleguide.html` (v2.0 neon direction, matches
`refs/ref1.png`–`ref3.png`). Open it and mirror its tokens/specs exactly.

## Goal

Port the SwiftUI shell (everything except GameScene) to the new neon-space design
language. GameScene/SpriteKit is task 30 — do not touch GameScene.swift here.

## 1. AppTheme.swift — new tokens

Replace the palette (keep `Color(hex:)` helper and modifier structure):

- `background` #05060F, `backgroundElevated` #0A0A18, `panel` #12121F,
  `panelSoft` #17172A, `line` #2A2A45, `muted` #8A8AA8, `mutedBright` #B9B9D6,
  `text` #F4F4FF
- `accentPurple` #A855F7, `accentBlue` #3B82F6, `accentCyan` #38BDF8,
  `notePink` #F048C6, `green` #34D399, `orange` #F97316, `red` #EF4444
- Back-compat aliases so existing call sites keep compiling:
  `accent` = accentPurple, `accentSecondary` = accentBlue, `good` = green,
  `danger` = red, `panelSecondary` = panelSoft
- `accentGradient`: linear purple → blue (110°-ish, leading→trailing is fine)
- `panelCard`: radius 16, near-black fill, 1px line stroke (keep API)
- New view helpers (small, reusable, in AppTheme.swift or a new
  `AutoWave/Features/Components.swift`):
  - `GradientCTAButtonStyle`: capsule, accentGradient fill, white heavy label,
    purple glow shadow (radius ~22). Secondary variant: dark fill + 1.5px
    gradient border (use `strokeBorder` with gradient).
  - `CircleIconButton(systemName:)`: dark circle + 2px gradient ring + glow,
    56pt default / 42pt compact.

## 2. Difficulty (Difficulty.swift + LibraryView.swift:491 tint extension)

- Retint (ORDER heaven→easy→normal→hard→hell NEVER changes):
  heaven green #34D399 · easy blue #3B82F6 · normal purple #A855F7 ·
  hard orange #F97316 · hell red #EF4444. Use exact hex (not system colors);
  move the tint extension onto Difficulty in Difficulty.swift or keep location,
  your call, but single source.
- Add `level: Int` (5/10/15/20/25) and `levelLabel` ("Lv. 5" …).
- Add `iconSystemName`: heaven "star", easy "star.fill", normal "sparkles",
  hard "flame.fill", hell — pick the most menacing existing SF Symbol
  (e.g. "exclamationmark.triangle.fill" or "bolt.fill"); must render on iOS 17.

## 3. ReadySheetView (LibraryView.swift:274) → ref2 modal

Keep presentation as a sheet/fullScreenCover from LibraryView (landscape), but
restyle content per styleguide "ReadyModal":

- Container: near-black elevated fill, radius 28, 1.5px purple→blue gradient
  border, glow. ✕ CircleIconButton top-right closes.
- Left column: album placeholder (rounded 24 gradient art using track palette
  color), track title + duration line (monospaced) — genre/waveform strip
  optional, skip if data absent.
- Right column stacked panels (radius 16, panelSoft):
  1. "난이도" — 5 DifficultyCards in a row: icon (tint colored), name, levelLabel.
     Selected: 2px accentPurple border + glow + slight scale. Unselected: 1px
     tint-alpha border, tint 9% fill.
  2. "LANE 개수" + caption "노트가 떨어지는 라인의 개수를 설정합니다." — circular
     chips for the existing lane options; selected = purple ring + glow.
  3. "배속" + caption "게임 속도를 설정합니다." — circular chips for the existing
     speed options; selected = purple ring. Replace the cycle-button UI with
     chips ONLY if the current speed model is an enumerable list; otherwise keep
     the cycle control restyled as a chip.
- Bottom: START GradientCTA (full width of right column), label "START" with
  play icon. Keeps the existing onStart behavior exactly.

## 4. Restyle (no structural changes)

- HomeView: new tokens; wordmark gradient now purple→blue; primary button uses
  GradientCTA; profile chip → small PlayerBadge look (circular avatar with
  gradient ring). Keep sections/navigation as-is (SongSelect merge is task 29).
- ImportView: dashed accentPurple gradient card, "파일 열기" GradientCTA.
- AnalysisView: ripple rings accentPurple, progress text mutedBright, add thin
  gradient progress bar if trivial.
- ResultsView: near-black bg + faint concentric ring motif, score in gradient
  text (monospaced heavy), judgment counts keep judgment colors, actions =
  GradientCTA "다시하기" + secondary "곡 선택" (rename from 라이브러리 if present).
- GameplayContainerView SwiftUI overlays only (pause overlay/pause button/speed
  control): pause card = near-black radius 20 + gradient border, buttons =
  GradientCTA/secondary; pause + speed buttons = CircleIconButton style.
  Do NOT touch the SpriteKit scene or its HUD.

## Constraints

- Swift 6, no third-party deps. Korean-first strings unchanged unless specified.
- Do not touch GameScene.swift, GameTheme.swift, BeatmapKit, or tests.
- Do not run git. Typecheck with at most 1–2 `xcodebuild build` attempts
  (prefix `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
  destination iPhone 17 Pro simulator). If you add a new file, note it in your
  summary so the caller can run `xcodegen generate`.

## Acceptance

1. App compiles (SwiftUI layer) with new tokens; no references to removed names.
2. Difficulty order untouched; new tints/levels/icons exposed and used by
   TrackRow badges + ReadyModal cards.
3. ReadyModal visually matches ref2 structure (cards row, circular chips, START).
4. All listed screens use only new palette (no leftover 0x6DDCFF cyan accent).
