# ScreenHighlighter 구현 정리

## 개요
- 프로젝트 경로: `/Users/tuesdaymorning/Devguru/screen_highlighter_codex`
- 목표: macOS에서 활성 창만 밝게 보이고 나머지 화면을 dim 처리하는 로컬 실행형 앱
- 배포 방식: App Store 미사용, 로컬 빌드 후 `.app` 직접 실행

## 사용 기술
- 언어: Swift
- 프레임워크: `AppKit`, `ApplicationServices` (AX/Accessibility)
- 앱 형태: 메뉴바(LSUIElement) 유틸리티 앱

## 현재 핵심 동작
- 전체 화면 오버레이(모든 디스플레이)에 dim layer 표시
- 활성 창 영역만 투명 컷아웃
- 메뉴바 컨트롤:
  - `Disable/Enable Highlight`
  - `Dim + / Dim -`
  - `Request Permission`
  - `Quit`

## 창 추적 방식(현재)
- 기본: Accessibility API로 활성 창 식별(`AXFocusedApplication`, `AXFocusedWindow`)
- 창 번호(`AXWindowNumber`)를 얻으면 `CGWindowList`로 실제 창 bounds를 추적
- 좌표계는 창별 캐시 모드(`raw`/`flipped`)를 사용해 방향 반전 최소화
- AX 실패 시 frontmost + CG fallback 경로 사용

## 주요 파일
- 앱 소스: `/Users/tuesdaymorning/Devguru/screen_highlighter_codex/ScreenHighlighter.swift`
- 빌드 스크립트: `/Users/tuesdaymorning/Devguru/screen_highlighter_codex/build.sh`
- 실행 스크립트: `/Users/tuesdaymorning/Devguru/screen_highlighter_codex/run.sh`
- 사용 안내: `/Users/tuesdaymorning/Devguru/screen_highlighter_codex/README.md`

## 빌드/실행
```bash
cd /Users/tuesdaymorning/Devguru/screen_highlighter_codex
./build.sh
./run.sh
```

## 확인된 이슈 상태
- dimming 동작: 작동
- X축 이동: 정상
- Y축 이동: 환경/속도에 따라 간헐 오차 보고됨

## 비고
- macOS 앱별로 AX/CG 좌표 특성이 달라 이동 중 샘플링 타이밍에 영향을 받을 수 있음
- 현재 코드는 상용 배포용(서명/공증)보다 로컬 실행 안정화에 초점
