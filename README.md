# MouseLang

macOS 한/영 입력 상태를 마우스 커서 옆에 실시간으로 표시해주는 유틸리티 앱.

영어를 입력해야 하는데 한글 모드인 줄 모르고 타이핑하다 지우는 실수, 혹은 그 반대 상황을 사전에 방지합니다.

## 스크린샷

```
  ┌─────┐
  │  한  │  ← 한글 입력 모드 (다크 테마)
  └─────┘

  ┌─────┐
  │  A  │  ← 영어 입력 모드 (다크 테마)
  └─────┘
```

## 주요 기능

| 기능 | 설명 |
|------|------|
| **커서 인디케이터** | 마우스 커서 우측 하단에 `한` / `A` 표시가 항상 따라다님 |
| **실시간 감지** | 한/영 전환 즉시 인디케이터 자동 변경 |
| **테마** | 다크(기본), 라이트, 리퀴드, 핑크, 민트 5종 |
| **투명도 조절** | 20% ~ 100% (5단계) |
| **위치 조절** | 버튼 클릭(5px) 또는 스크롤 조절 모드(2px) |
| **메뉴바 앱** | 상단 메뉴바에서 모든 설정 제어, Dock 아이콘 없음 |

## 요구 사항

- macOS 13.0 (Ventura) 이상
- Apple Silicon (arm64) Mac
- Xcode Command Line Tools (`swiftc` 컴파일러)

## 빌드 및 실행

### 1. Xcode Command Line Tools 설치 (최초 1회)

```bash
xcode-select --install
```

### 2. 빌드

```bash
git clone <repository-url>
cd mouse-lang
chmod +x build.sh
./build.sh
```

빌드 성공 시 `build/MouseLang.app`이 생성됩니다.

### 3. 실행

```bash
open build/MouseLang.app
```

상단 메뉴바에 🌐 아이콘이 나타나면 정상 실행된 것입니다.

### 4. 종료

메뉴바 🌐 아이콘 클릭 → **종료** (⌘Q)

## 메뉴 구성

```
🌐
├── 표시 끄기 / 켜기        ⌘T
├── ────────────
├── 테마                   ▶  다크 ✓ | 라이트 | 리퀴드 | 핑크 | 민트
├── 투명도                 ▶  100% ✓ | 80% | 60% | 40% | 20%
├── 위치 조절              ▶  현재: X+18, Y-28
│                             🎯 위치 조절 모드 (스크롤로 이동)
│                             ↑ 위로 / ↓ 아래로 / ← 왼쪽 / → 오른쪽
│                             ↺ 초기화
├── ────────────
└── 종료                    ⌘Q
```

## 위치 조절 방법

| 방법 | 조작 | 이동 단위 |
|------|------|-----------|
| **버튼 방식** | 메뉴에서 ↑↓←→ 클릭 | 5px |
| **스크롤 방식** | 🎯 조절 모드 ON → 마우스 스크롤 | 2px |

- 조절 모드 활성화 시 인디케이터에 노란색 테두리가 표시됩니다.
- **↺ 초기화**로 기본 위치(X+18, Y-28)로 복원할 수 있습니다.

## 프로젝트 구조

```
mouse-lang/
├── Sources/
│   ├── main.swift                # 앱 엔트리 포인트
│   ├── AppDelegate.swift         # 메뉴바, 마우스 추적, 설정 관리
│   ├── InputSourceManager.swift  # Carbon TIS API 한/영 감지
│   ├── IndicatorWindow.swift     # 투명 플로팅 윈도우
│   └── Theme.swift               # 테마 정의
├── Info.plist                    # 앱 설정 (LSUIElement)
├── build.sh                      # 빌드 스크립트
└── README.md
```

## 기술 스택

| 구분 | 기술 |
|------|------|
| 언어 | Swift |
| UI | AppKit (NSWindow, NSStatusBar, NSView) |
| 입력 소스 감지 | Carbon Framework (TISCopyCurrentKeyboardInputSource) |
| 입력 변경 알림 | DistributedNotificationCenter |
| 마우스 추적 | Timer + NSEvent.mouseLocation (60fps) |
| 빌드 | swiftc (Xcode Command Line Tools) |

## 참고

- [YouType](https://github.com/freefelt/YouType/) - 영감을 준 프로젝트

## 라이선스

MIT License
