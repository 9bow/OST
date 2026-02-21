[🇬🇧 English](README.md) | 🇰🇷 **한국어** | [🇨🇳 中文](README.zh.md) | [🇯🇵 日本語](README.ja.md)

# OST — On-Screen Translator

macOS를 위한 실시간 음성 인식 및 번역 오버레이 앱입니다.

시스템 오디오를 캡처하여 Apple Speech 프레임워크를 사용해 음성을 텍스트로 변환하고, 번역된 자막을 플로팅 오버레이 창에 표시합니다. YouTube, 팟캐스트, Zoom/Teams 회의 등 모든 오디오 소스에서 작동합니다.

## 스크린샷

![YouTube 영상 위 번역 오버레이](assets/overlay-demo.png)

<details>
<summary>더 보기</summary>

| 메뉴 바 | 설정 — 디스플레이 |
|:---:|:---:|
| ![메뉴 바](assets/menubar.png) | ![디스플레이 설정](assets/settings-display.png) |

| 설정 — 언어 | 설정 — 초기 설정 |
|:---:|:---:|
| ![언어 설정](assets/settings-languages.png) | ![초기 설정](assets/settings-setup.png) |

| 세션 기록 |
|:---:|
| ![세션 기록](assets/session-history.png) |

</details>

## 면책 조항

이 프로젝트는 [Claude](https://claude.ai/) (Anthropic의 AI 어시스턴트)에 의해 전적으로 작성되었습니다. 코드, 빌드 스크립트, 문서, CI/CD 구성 모두 AI 지원 개발을 통해 생성되었습니다. 기능적으로 동작하지만, 공식적인 코드 리뷰를 거치지 않았으므로 사용에 유의하시기 바랍니다.

## 기능

- **실시간 시스템 오디오 캡처** — ScreenCaptureKit (16kHz 모노 PCM)
- **음성 인식** — SFSpeechRecognizer (온디바이스 또는 서버 기반)
- **실시간 번역** — Apple Translation 프레임워크 — 음성 인식 중에도 실시간으로 번역 (최종 결과를 기다리지 않음)
- **이중 디스플레이 모드**:
  - **통합** — 인식 텍스트와 번역 텍스트를 하나의 오버레이에 표시
  - **분할** — 인식 창과 번역 창을 분리하여 각각 독립적으로 배치 가능
- **플로팅 오버레이** — 크기 조절, 이동 가능, 항상 최상위 표시, 외관 커스터마이징
- **잠금/잠금 해제** — 잠금 = 클릭 통과, 잠금 해제 = 이동/크기 조절/스크롤
- **스크롤 가능한 자막 기록** (자동 스크롤)
- **외관 커스터마이징** — 원문/번역 텍스트별 글꼴 크기/색상, 배경색/투명도
- **자동 언어 감지** (영어, 한국어, 일본어, 중국어)
- **스마트 텍스트 처리** — 문장 기반 분할, 음성 중단 감지, 중복 필터링, 구두점 정리
- **세션 기록** 및 내보내기
- **메뉴 바 앱** — Dock 아이콘 없음, 최소 리소스 사용

## 요구 사항

- macOS 15.0 (Sequoia) 이상
- Apple Silicon (arm64)

## 설치

### 방법 A: 빌드된 바이너리 다운로드 (권장)

1. [최신 릴리즈](https://github.com/9bow/OST.git/releases/latest)에서 `OST.zip` 다운로드
2. 압축 해제 후 `OST.app`을 응용 프로그램 폴더로 이동
3. 처음 실행 시 macOS가 앱을 차단하면:
   ```bash
   xattr -dr com.apple.quarantine /Applications/OST.app
   ```

### 방법 B: 소스에서 빌드

**Xcode Command Line Tools** 필요:

```bash
xcode-select --install
```

자세한 내용은 아래 [빌드](#빌드) 섹션을 참조하세요.

## 설정 가이드

### 1단계: 필수 권한 부여

처음 실행 시 macOS가 다음 권한을 요청합니다. 요청이 나타나지 않으면 수동으로 활성화하세요:

| 권한 | 용도 | 활성화 방법 |
|---|---|---|
| **화면 기록** | ScreenCaptureKit을 통한 시스템 오디오 캡처 | 시스템 설정 > 개인정보 보호 및 보안 > 화면 기록 > OST 활성화 |
| **음성 인식** | SFSpeechRecognizer 접근 | 시스템 설정 > 개인정보 보호 및 보안 > 음성 인식 > OST 활성화 |

> 권한 부여 후 변경 사항을 적용하려면 OST를 재시작해야 할 수 있습니다.

### 2단계: Siri 및 받아쓰기 활성화

음성 인식 (특히 서버 기반)에는 Siri 및 받아쓰기가 활성화되어 있어야 합니다:

1. **시스템 설정 > Siri 및 Spotlight** 열기
2. **Siri** (또는 "들어볼 항목...") 활성화
3. 온디바이스 인식만 사용하는 경우 Siri가 활성화되어 있지 않아도 됩니다 — 단, 음성 모델을 다운로드해야 합니다 (3단계 참조)

### 3단계: 온디바이스 음성 모델 다운로드 (권장)

더 빠르고, 오프라인에서도 작동하며, 더 안정적인 인식을 위해:

1. **시스템 설정 > 일반 > 키보드 > 받아쓰기** 열기
2. **언어** 아래에서 소스 언어의 음성 모델 다운로드 (예: 영어, 한국어, 일본어)
3. 다운로드 후 OST 설정 > 언어 탭에서 **"온디바이스 인식"** 활성화

> 온디바이스 모델이 없으면 서버 기반 인식이 사용됩니다. 인터넷이 필요하며 지연 시간이 길어질 수 있습니다.

### 4단계: 번역 언어 팩 다운로드 (권장)

Apple Translation 프레임워크를 사용한 오프라인 번역을 위해:

1. **시스템 설정 > 일반 > 언어 및 지역 > 번역 언어** 열기
2. 필요한 언어 쌍 다운로드 (예: 영어 ↔ 한국어)

> 번역 언어 팩이 없으면 오프라인 번역이 작동하지 않습니다.

## 빌드

```bash
# 저장소 클론
git clone https://github.com/9bow/OST.git
cd OST

# 전체 빌드 → build/OST.app 생성
./build.sh

# 타입 체크만 (바이너리 없음)
./build.sh --typecheck

# 클린 빌드
./build.sh --clean

# 실행
open build/OST.app
```

Xcode 프로젝트가 필요하지 않습니다. 빌드 스크립트가 `xcrun swiftc`를 통해 모든 Swift 소스를 컴파일합니다.

> 처음 실행 시 macOS가 앱을 차단하면 다음을 실행하세요:
> ```bash
> xattr -dr com.apple.quarantine build/OST.app
> ```

## 사용법

### 세션 시작

1. 메뉴 바에서 **자막 아이콘**을 클릭
2. 소스 및 타겟 언어 선택 (또는 자동 감지를 위해 "Auto" 사용)
3. **Start**를 클릭하여 시스템 오디오 캡처 시작
4. 실시간 음성 인식 및 번역이 표시되는 오버레이 창이 나타남

### 오버레이 조작

| 동작 | 방법 |
|---|---|
| **잠금/잠금 해제** | 메뉴 바 > Lock Overlay, 또는 설정 > 디스플레이 > 오버레이 창 |
| **이동** | 잠금 해제 후 오버레이 창을 드래그 |
| **크기 조절** | 잠금 해제 후 창 가장자리를 드래그 |
| **스크롤** | 잠금 해제 후 자막 기록을 스크롤 |
| **위치 초기화** | 설정 > 디스플레이 > "Reset All Overlay Windows" |

- **잠금 모드**: 오버레이가 클릭을 통과합니다 — 뒤에 있는 창과 정상적으로 상호작용 가능
- **잠금 해제 모드**: 드래그하여 이동, 가장자리로 크기 조절, 자막 기록 스크롤. 최신 텍스트로 자동 스크롤

### 디스플레이 모드

**설정 > 디스플레이 > 모드**에서 설정:

- **통합**: 원문과 번역 텍스트를 하나의 창에 표시
- **분할**: 인식 (원문)과 번역을 두 개의 별도 창으로 분리. 각 창을 독립적으로 배치 및 크기 조절 가능. 잠금/잠금 해제는 두 창에 동시에 적용

### 팁

- **음성 중단**: 설정 > 디스플레이 > "Speech Pause" 슬라이더로 조절. 짧은 값은 텍스트를 더 빠르게 확정하고, 긴 값은 자연스러운 문장 끝을 기다림
- **자막 만료**: 오래된 자막은 설정된 시간 후 자동으로 사라짐 (기본값 10초)
- **최대 줄 수**: 동시에 표시되는 자막 항목 수를 조절
- **세션 기록**: 메뉴 바 > Session History에서 과거 음성 인식 세션을 확인. 세션을 내보내기 가능

## 아키텍처

```
ScreenCaptureKit (16kHz mono) → SpeechRecognizer → AppState → TranslationService → Overlay Views
     SystemAudioCapture              SFSpeech          entries      Translation.framework     NSPanel
```

### 소스 구조

```
OST/Sources/
├── App/             AppState, OSTApp, WindowManager, Logger, SessionRecorder
├── Audio/           SystemAudioCapture (ScreenCaptureKit)
├── Speech/          SpeechRecognizer, SupportedLanguages
├── Translation/     TranslationService, TranslationConfig
├── Settings/        UserSettings
├── UI/              SubtitleView, RecognitionOverlayView, TranslationOverlayView,
│                    OverlayWindow, MenuBarView, SettingsView, FontSettingsView, etc.
└── Accessibility/   AccessibilityManager
```

## 문제 해결

| 문제 | 해결 방법 |
|---|---|
| 오디오가 캡처되지 않음 | 시스템 설정에서 화면 기록 권한 부여 후 OST 재시작 |
| 음성 인식이 작동하지 않음 | 음성 인식 권한 부여; Siri 및 받아쓰기 활성화 확인 |
| 번역이 나타나지 않음 | 시스템 설정 > 번역 언어에서 번역 언어 팩 다운로드 |
| 오버레이가 보이지 않지만 클릭을 차단함 | 설정 > 디스플레이 > "Reset All Overlay Windows"로 기본 위치 복원 |
| macOS가 앱을 차단함 | `xattr -dr com.apple.quarantine build/OST.app` 실행 |
| 온디바이스 인식에서 결과가 없음 | 시스템 설정 > 키보드 > 받아쓰기에서 해당 언어의 음성 모델 다운로드 |

## 알려진 문제

- **끝점 감지 (EPD)** — 음성 분할에 적절한 끝점 감지 대신 일시 중지 타이머와 문장 경계 감지를 사용합니다. 자막 경계가 문장 중간에서 분할되거나 관련 없는 구문이 합쳐질 수 있습니다.
- **자동 언어 감지** — 자동 감지는 처음 ~15자에 대해 NLLanguageRecognizer를 사용하므로, 짧거나 모호한 입력에서 언어를 잘못 식별할 수 있습니다. 감지는 세션당 한 번만 실행됩니다.
- **번역 일관성** — 번역은 음성 세그먼트별로 트리거됩니다. 짧거나 단편적인 세그먼트는 덜 일관된 번역을 생성할 수 있습니다.
- **음성 인식 재시작 간격** — SFSpeechRecognizer의 인식 작업은 ~60초 후 만료되어 자동으로 재시작됩니다. 중복 감지로 텍스트 중복을 최소화하지만, 인식에 짧은 공백이 발생할 수 있습니다.

## 라이선스

[MIT](LICENSE)
