# ScreenHighlighter 설치 가이드

현재 집중 중인 창만 밝게 보여주고, 나머지 화면은 어둡게 처리하는 macOS 유틸리티입니다.

## 요구 사항

- **macOS 13.0 (Ventura)** 이상
- **Apple Silicon** (M1 / M2 / M3) Mac

---

## 설치 방법

### 1. DMG 파일 전달

`build/ScreenHighlighter.dmg` 파일을 다른 맥북으로 복사합니다.

- **AirDrop** — 가장 간편
- **USB / 외장 드라이브**
- **iCloud Drive / Google Drive** 등 클라우드

### 2. 앱 설치

1. `ScreenHighlighter.dmg`를 **더블클릭**하여 마운트
2. 열린 창에서 `ScreenHighlighter.app`을 **Applications 폴더로 드래그**
3. DMG를 추출(꺼내기)

### 3. 처음 실행 (Gatekeeper 우회)

개발자 서명이 없는 앱이므로, 처음 실행 시 Gatekeeper 차단이 발생합니다.

**방법 A — 우클릭으로 열기:**
1. Finder → Applications → `ScreenHighlighter.app` **우클릭**
2. **"열기"** 선택
3. 경고 팝업에서 다시 **"열기"** 클릭

**방법 B — 터미널 명령어:**
```bash
xattr -cr /Applications/ScreenHighlighter.app
open /Applications/ScreenHighlighter.app
```

### 4. 손쉬운 사용(Accessibility) 권한 허용

앱이 다른 창의 위치를 읽으려면 이 권한이 필수입니다.

1. **시스템 설정** → **개인정보 보호 및 보안** → **손쉬운 사용**
2. `ScreenHighlighter` 항목을 찾아 **토글 ON**
3. 항목이 없으면 **+** 버튼으로 직접 추가

> [!IMPORTANT]
> 이 권한 없이는 하이라이트 기능이 동작하지 않습니다.

---

## 사용법

앱 실행 후 메뉴바에 **"Focus"** 아이콘이 나타납니다.

| 메뉴 항목 | 단축키 | 기능 |
|---------|-------|------|
| Disable/Enable Highlight | `T` | 하이라이트 켜기/끄기 |
| Dim + | `=` | 배경 더 어둡게 |
| Dim - | `-` | 배경 더 밝게 |
| Request Permission | `P` | 손쉬운 사용 권한 요청 |
| Quit | `Q` | 앱 종료 |

---

## 소스에서 직접 빌드 (개발자용)

Xcode Command Line Tools가 설치된 Mac에서:

```bash
# 빌드
bash build.sh

# 배포 패키지(DMG) 생성
bash package.sh

# 실행
bash run.sh
```

---

## 문제 해결

| 증상 | 해결 |
|-----|------|
| "손상된 앱" 경고 | 터미널에서 `xattr -cr /Applications/ScreenHighlighter.app` 실행 |
| 하이라이트 안 됨 | 시스템 설정 → 손쉬운 사용 권한 확인 |
| 앱이 보이지 않음 | 메뉴바의 "Focus" 텍스트 확인 (Dock에는 표시 안 됨) |
