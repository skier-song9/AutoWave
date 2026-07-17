# AutoWave

AutoWave는 로컬 오디오를 분석해 플레이 가능한 리듬 게임 비트맵으로 자동 변환합니다. 다섯 난이도와 물결 파동형 노트 디자인으로 음악을 새로운 방식으로 플레이할 수 있습니다.

AutoWave is an iOS rhythm game that automatically generates playable beatmaps from local audio files. It provides five difficulties—천국, 쉬움, 보통, 어려움, and 지옥—and uses a distinctive wave-ripple note design.

## Architecture

- SwiftUI provides the app shell and screens.
- SpriteKit renders the gameplay scene and interactive notes.
- BeatmapKit is the vDSP-based audio-analysis and beatmap-generation pipeline.
- SwiftData persists tracks, beatmaps, and score records.
- AVFoundation handles local audio ingestion and decoding.

## Build and test

Requirements: Xcode 26.6 and XcodeGen.

Regenerate the Xcode project after adding or removing source files:

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
├── AutoWave.xcodeproj/
│   ├── project.pbxproj
│   ├── project.xcworkspace/
│   │   ├── contents.xcworkspacedata
│   │   └── xcshareddata/WorkspaceSettings.xcsettings
│   └── xcshareddata/xcschemes/AutoWave.xcscheme
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
│   │   │   ├── OnsetDetector.swift
│   │   │   ├── SpectralAnalyzer.swift
│   │   │   └── TempoEstimator.swift
│   │   └── Models/
│   │       ├── Beatmap.swift
│   │       ├── BeatmapEntity.swift
│   │       ├── Difficulty.swift
│   │       ├── Note.swift
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
│   │   ├── Import/
│   │   │   ├── AudioImportService.swift
│   │   │   └── ImportView.swift
│   │   ├── Library/LibraryView.swift
│   │   └── ThemePalette+Color.swift
│   ├── Info.plist
│   └── Resources/Assets.xcassets/
│       ├── AccentColor.colorset/Contents.json
│       ├── AppIcon.appiconset/
│       │   ├── AppIcon-1024.png
│       │   └── Contents.json
│       └── Contents.json
├── AutoWaveTests/
│   ├── AnalysisViewModelTests.swift
│   ├── AudioImportServiceTests.swift
│   ├── BeatmapGeneratorTests.swift
│   ├── BeatmapKitAnalysisTests.swift
│   ├── EndToEndPipelineTests.swift
│   ├── JudgmentEngineTests.swift
│   ├── ModelCodingTests.swift
│   ├── SmokeTests.swift
│   └── VisualizerTapTests.swift
└── scripts/generate_app_icon.py
```

## Scope

YouTube ingestion is intentionally excluded. Downloading or converting media from third-party sources requires careful authorization under [App Store Review Guideline 5.2.3](https://developer.apple.com/app-store/review/guidelines/#5.2.3), and access to YouTube is also governed by [YouTube's Terms of Service](https://www.youtube.com/static?template=terms). AutoWave therefore accepts local audio files only.
