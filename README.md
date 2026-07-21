# AutoWave

AutoWave는 로컬 오디오를 분석해 플레이 가능한 리듬 게임 비트맵으로 자동 변환합니다.
다섯 난이도와 네온 스페이스 디자인, 원근형 레인 위로 떨어지는 글로시 노트로 음악을
새로운 방식으로 플레이할 수 있습니다.

AutoWave is an iOS rhythm game that automatically generates playable beatmaps from
local audio files. It ships five difficulties—천국, 쉬움, 보통, 어려움, 지옥—a
neon-space design language, and a perspective lane field with glossy falling notes.

## Gameplay

- **곡 선택 (SongSelect)**: 원형 앨범 디스크 캐러셀을 세로로 스와이프해 곡을 고릅니다.
  포커스된 디스크를 탭하면 준비 모달, 길게 누르면 삭제 확인 다이얼로그가 열립니다.
- **준비 모달 (ReadyModal)**: 난이도(천국/쉬움/보통/어려움/지옥)와 배속(x0.5–x2.0)을
  고릅니다. 레인 수는 난이도에 고정입니다 — 천국·쉬움 4, 보통 5, 어려움 6, 지옥 7.
- **인게임**: 원근 하이웨이 위로 노트가 떨어지고, 하단 리셉터 라인에서 판정합니다.
  좌·우 상단의 원형 링 게이지가 각각 체력과 점수/콤보를 표시합니다.
- **동시노트**: 항상 왼손/오른손 영역(레인을 ⌈n/2⌉에서 분할)에 하나씩 배치되어
  양손으로 칠 수 있습니다.
- **결과**: 점수·최대 콤보·판정별 카운트를 보여주고 다시하기/곡 선택으로 이동합니다.

## Architecture

- **SwiftUI** — 앱 셸과 화면(곡 선택, 준비 모달, 가져오기, 분석, 결과).
- **SpriteKit** — 게임플레이 씬(레인 필드, 리셉터, 노트/드래그, 링 게이지 HUD, 이펙트).
- **BeatmapKit** — vDSP 기반 오디오 분석 + 비트맵 생성 파이프라인(순수·결정론적).
  - 레거시 온셋 경로와, 실제 음원에서 쓰이는 MIR 경로(음악적 객체 → 역할별 트래킹)
    두 갈래를 가집니다. 난이도별 밀도·화음·드래그·시퀀스 간격 정책은 `MIRModels`의
    `DifficultyLayerPolicy`가 관장합니다.
- **SwiftData** — 트랙·비트맵·점수·프로필을 영속화.
- **AVFoundation** — 로컬 오디오 수집과 디코딩.

디자인 시스템의 단일 소스는 `docs/design/styleguide.html`(네온 스페이스, 한국어 우선,
외부 에셋 없는 단일 HTML 파일)입니다.

## Build and test

Requirements: Xcode 26.6 and XcodeGen.

소스 파일 추가/삭제 후에는 Xcode 프로젝트를 재생성합니다:

```bash
xcodegen generate
```

Build:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project AutoWave.xcodeproj -scheme AutoWave \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Test:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project AutoWave.xcodeproj -scheme AutoWave \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Project layout

```text
.
├── AGENTS.md
├── CLAUDE.md
├── project.yml
├── README.md
├── docs/
│   ├── design/styleguide.html        # 디자인 시스템 단일 소스 (네온 스페이스)
│   ├── manual-test-checklist.md
│   └── plans/
├── AutoWave/
│   ├── App/
│   │   ├── AutoWaveApp.swift
│   │   └── RootView.swift
│   ├── Core/
│   │   ├── AudioEngine/VisualizerTap.swift
│   │   ├── BeatmapKit/
│   │   │   ├── AnalysisResult.swift
│   │   │   ├── AudioDecoder.swift
│   │   │   ├── BeatmapGenerator.swift
│   │   │   ├── DifficultyProfile.swift
│   │   │   ├── MIRAnalyzers.swift
│   │   │   ├── MIRModels.swift
│   │   │   ├── MusicalEventAdapter.swift
│   │   │   ├── OnsetDetector.swift
│   │   │   ├── SpectralAnalyzer.swift
│   │   │   └── TempoEstimator.swift
│   │   └── Models/
│   │       ├── AppTheme.swift
│   │       ├── Beatmap.swift
│   │       ├── BeatmapEntity.swift
│   │       ├── Difficulty.swift
│   │       ├── GameplayRules.swift
│   │       ├── GameTheme.swift
│   │       ├── Note.swift
│   │       ├── ProfileEntity.swift
│   │       ├── ScoreRecord.swift
│   │       ├── ThemePalette.swift
│   │       └── TrackEntity.swift
│   ├── Features/
│   │   ├── Analysis/
│   │   │   ├── AnalysisView.swift
│   │   │   └── AnalysisViewModel.swift
│   │   ├── Gameplay/
│   │   │   ├── GameScene.swift
│   │   │   ├── GameplayContainerView.swift
│   │   │   ├── GameplayViewModel.swift
│   │   │   ├── JudgmentEngine.swift
│   │   │   └── ResultsView.swift
│   │   ├── Home/
│   │   │   ├── HomeView.swift
│   │   │   ├── ProfileView.swift
│   │   │   ├── SongSelectView.swift
│   │   │   └── TrackDeletionService.swift
│   │   ├── Import/
│   │   │   ├── AudioImportService.swift
│   │   │   └── ImportView.swift
│   │   ├── Library/LibraryView.swift
│   │   └── ThemePalette+Color.swift
│   ├── Info.plist
│   └── Resources/Assets.xcassets/
├── AutoWaveTests/
│   ├── AnalysisViewModelTests.swift
│   ├── AudioImportServiceTests.swift
│   ├── BeatmapGeneratorTests.swift
│   ├── BeatmapKitAnalysisTests.swift
│   ├── EndToEndPipelineTests.swift
│   ├── GameplayRulesTests.swift
│   ├── GameplayStabilityTests.swift
│   ├── GameplayStartRegressionTests.swift
│   ├── GameplaySummaryTests.swift
│   ├── JudgmentEngineTests.swift
│   ├── MIRGenerationTests.swift
│   ├── ModelCodingTests.swift
│   ├── ProfileEntityTests.swift
│   ├── SmokeTests.swift
│   ├── TrackDeletionServiceTests.swift
│   └── VisualizerTapTests.swift
└── scripts/generate_app_icon.py
```

## Scope

YouTube ingestion is intentionally excluded. Downloading or converting media from
third-party sources requires careful authorization under [App Store Review Guideline 5.2.3](https://developer.apple.com/app-store/review/guidelines/#5.2.3),
and access to YouTube is also governed by [YouTube's Terms of Service](https://www.youtube.com/static?template=terms).
AutoWave therefore accepts local audio files only.
