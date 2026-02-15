<p align="center">
  <h1 align="center">🔦 ScreenHighlighter</h1>
  <p align="center">
    <strong>집중 모드를 위한 macOS 화면 하이라이터</strong>
  </p>
  <p align="center">
    현재 활성 창만 밝게, 나머지는 어둡게 — 집중력을 높여주는 심플한 유틸리티
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/platform-macOS%2013+-blue?style=flat-square" />
    <img src="https://img.shields.io/badge/chip-Apple%20Silicon-black?style=flat-square&logo=apple" />
    <img src="https://img.shields.io/badge/swift-5.9+-orange?style=flat-square&logo=swift&logoColor=white" />
    <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
  </p>
</p>

---

## ✨ 주요 기능

- 🪟 **포커스 하이라이팅** — 현재 활성 창만 밝게, 나머지 화면은 디밍 처리
- ⚡ **120fps 트래킹** — 창 이동/리사이즈를 부드럽게 실시간 추적
- 🎚️ **디밍 강도 조절** — 메뉴바에서 어둡기 단계 조절 가능
- 🖥️ **멀티 모니터 지원** — 여러 디스플레이 환경에서도 동작
- 🪶 **초경량** — 단일 Swift 파일, 외부 의존성 없음

## 📋 요구 사항

| 항목 | 조건 |
|-----|------|
| OS | macOS 13 Ventura 이상 |
| Chip | Apple Silicon (M1/M2/M3/M4) |
| 빌드 도구 | Xcode Command Line Tools |
| 권한 | 손쉬운 사용(Accessibility) |

## 🚀 빠른 시작

### 소스에서 빌드 & 실행

```bash
git clone https://github.com/Devguru-J/Screen_highlighter_MacOS.git
cd Screen_highlighter_MacOS

# 빌드
chmod +x build.sh run.sh package.sh
./build.sh

# 실행
./run.sh
```

### DMG 설치 파일 생성

다른 Mac으로 옮길 때 사용합니다:

```bash
./package.sh
# → build/ScreenHighlighter.dmg 생성
```

> [!TIP]
> DMG 파일을 AirDrop이나 USB로 복사하면 빌드 환경 없이도 설치할 수 있습니다.

## 📦 설치 (DMG)

1. `ScreenHighlighter.dmg`를 더블클릭
2. `ScreenHighlighter.app`을 **Applications** 폴더로 드래그
3. 처음 실행 시 **우클릭 → 열기** (Gatekeeper 우회)

> [!IMPORTANT]
> **손쉬운 사용 권한**이 필수입니다.
> 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → ScreenHighlighter **ON**

자세한 설치 방법은 [INSTALL.md](./INSTALL.md)를 참고하세요.

## 🎮 사용법

앱 실행 후 메뉴바에 **"Focus"** 아이콘이 나타납니다:

| 메뉴 | 단축키 | 설명 |
|------|-------|------|
| Enable/Disable Highlight | `T` | 하이라이트 켜기/끄기 토글 |
| Dim + | `=` | 배경을 더 어둡게 |
| Dim - | `-` | 배경을 더 밝게 |
| Request Permission | `P` | 접근성 권한 요청 팝업 |
| Quit | `Q` | 앱 종료 |

## 🏗️ 프로젝트 구조

```
screen-highlighter/
├── ScreenHighlighter.swift   # 앱 전체 소스 (단일 파일)
├── build.sh                  # 빌드 스크립트
├── run.sh                    # 실행 스크립트
├── package.sh                # DMG 패키징 스크립트
├── INSTALL.md                # 상세 설치 가이드
└── build/                    # 빌드 결과물 (gitignore)
    ├── ScreenHighlighter.app
    └── ScreenHighlighter.dmg
```

## 🔧 동작 원리

1. **AX (Accessibility) API**로 현재 포커스된 창의 위치와 크기를 실시간 조회
2. **CGWindowList API**를 보조로 활용하여 정확도 향상
3. 모든 스크린에 **투명 오버레이 윈도우**를 배치
4. 오버레이에 디밍을 채우고, 포커스 창 영역만 **clear blend**로 투명하게 제거

## 🐛 문제 해결

| 증상 | 해결 방법 |
|-----|----------|
| "손상된 앱" 경고 | `xattr -cr /Applications/ScreenHighlighter.app` |
| 하이라이트가 안 됨 | 시스템 설정 → 손쉬운 사용 권한 확인 |
| 앱이 안 보임 | 메뉴바에 "Focus" 텍스트로 표시됨 (Dock에는 없음) |

## 📄 라이선스

[MIT License](./LICENSE) — 자유롭게 사용, 수정, 배포할 수 있습니다.
