# Codex Handoff — Task 12: Home screen + profile

Read `AGENTS.md` first. Owner request: improve the main screen with future
multiplayer and account-linking in mind, and add a profile the user can set up.
Local-only for now — no networking, no real account systems.

## 1. ProfileEntity (SwiftData)

`AutoWave/Core/Models/ProfileEntity.swift` — @Model: `nickname: String`
(default "플레이어"), `avatarSymbol: String` (SF Symbol name, default
"water.waves"), `avatarTint: String` (hex, default "#4FC3F7"),
`createdAt: Date`. Register in the app's Schema. Single-row semantics: a
`static func current(in context: ModelContext) -> ProfileEntity` that fetches
or creates the one profile.

## 2. HomeView (new main screen)

`AutoWave/Features/Home/HomeView.swift`, becomes the root (RootView shows
HomeView instead of the current list):

- Top: animated wave glyph + "AutoWave" title, subtle looping ripple animation
  (reuse SwiftUI-only animation style from AnalysisView; no SpriteKit here).
- Profile chip (top-trailing): avatar symbol in tinted circle + nickname; tap →
  ProfileView sheet.
- Primary buttons (large, vertical stack, Korean):
  - "플레이" → LibraryView (existing navigation flow untouched from there)
  - "음원 가져오기" → ImportView
- Secondary section "곧 만나요" with two DISABLED rows (greyed, no action):
  "멀티플레이 (준비 중)" with `person.2.fill`, "계정 연동 (준비 중)" with
  `link.circle`. These are visual placeholders only — do not scaffold any
  networking/auth code behind them.
- Bottom: latest play summary if any ScoreRecord exists ("최근 기록: <track> ·
  <difficulty displayName> · <score>점"), else nothing.

## 3. ProfileView

`AutoWave/Features/Home/ProfileView.swift` (sheet):

- Nickname TextField (max 12 chars, trim whitespace, disallow empty — revert
  to previous on invalid).
- Avatar picker: horizontal grid of 8 SF symbols: water.waves, bolt.fill,
  music.note, flame.fill, star.fill, moon.stars.fill, pawprint.fill,
  gamecontroller.fill. Tint picker: 6 fixed colors (#4FC3F7, #FF4081, #26C6DA,
  #FFCA7A, #B39DDB, #80DEEA) as tappable circles.
- Saves to ProfileEntity on change (SwiftData autosave or explicit save).
- "완료" button dismisses.

## 4. Tests

`AutoWaveTests/ProfileEntityTests.swift`: `current(in:)` creates exactly one
row on first call and returns the same row on repeat calls (in-memory
container); nickname validation helper (extract it as a testable pure
function) rejects empty/whitespace and >12 chars.

## 5. Verification

- `xcodegen generate` after adding files. All existing tests stay green.
- Typecheck only; orchestrator runs the simulator gate and screenshots the
  home screen. Korean UI strings; keep navigation to existing screens intact
  (Library row tap behavior, analysis flow, gameplay unchanged).
