[🇬🇧 English](README.md) | [🇰🇷 한국어](README.ko.md) | 🇨🇳 **中文** | [🇯🇵 日本語](README.ja.md)

# OST — On-Screen Translator

macOS 实时语音识别与翻译叠加层应用。

捕获系统音频，使用 Apple Speech 框架将语音转换为文本，并在浮动叠加窗口中显示翻译字幕。适用于任何音频来源——YouTube、播客、Zoom/Teams 会议等。

## 截图

![YouTube 视频上的翻译叠加层](assets/overlay-demo.png)

<details>
<summary>更多截图</summary>

| 菜单栏 | 设置 — 显示 |
|:---:|:---:|
| ![菜单栏](assets/menubar.png) | ![显示设置](assets/settings-display.png) |

| 设置 — 语言 | 设置 — 初始设置 |
|:---:|:---:|
| ![语言设置](assets/settings-languages.png) | ![初始设置](assets/settings-setup.png) |

| 会话历史 |
|:---:|
| ![会话历史](assets/session-history.png) |

</details>

## 免责声明

本项目完全由 [Claude](https://claude.ai/)（Anthropic 的 AI 助手）编写。代码、构建脚本、文档和 CI/CD 配置均通过 AI 辅助开发生成。虽然功能正常，但代码未经过正式的人工代码审查——请谨慎使用。

## 功能

- **实时系统音频捕获** — ScreenCaptureKit（16kHz 单声道 PCM）
- **语音转文字** — SFSpeechRecognizer（设备端或服务器端）
- **实时翻译** — Apple Translation 框架——在语音识别过程中实时翻译，无需等待最终结果
- **双显示模式**：
  - **合并** — 在单个叠加层中同时显示识别文本和翻译文本
  - **分离** — 将识别窗口和翻译窗口分开，可独立放置
- **浮动叠加层** — 可调整大小、可移动、始终置顶、可自定义外观
- **锁定/解锁** — 锁定 = 点击穿透，解锁 = 移动/调整大小/滚动
- **可滚动的字幕历史**（自动滚动）
- **可自定义外观** — 原文/译文各自的字体大小/颜色、背景颜色/透明度
- **自动语言检测**（英语、韩语、日语、中文）
- **智能文本处理** — 基于句子的分割、语音停顿检测、重复过滤、标点清理
- **会话历史**记录与导出
- **菜单栏应用** — 无 Dock 图标，占用资源极少

## 系统要求

- macOS 15.0（Sequoia）或更高版本
- Apple Silicon（arm64）

## 安装

### 方式 A：下载预构建二进制文件（推荐）

1. 从[最新版本](https://github.com/9bow/OST.git/releases/latest)下载 `OST.zip`
2. 解压并将 `OST.app` 移动到"应用程序"文件夹
3. 如果 macOS 在首次运行时阻止应用：
   ```bash
   xattr -dr com.apple.quarantine /Applications/OST.app
   ```

### 方式 B：从源代码构建

需要 **Xcode Command Line Tools**：

```bash
xcode-select --install
```

详细说明请参阅下方[构建](#构建)部分。

## 设置指南

### 第 1 步：授予必要权限

首次启动时，macOS 会提示授予以下权限。如未提示，请手动启用：

| 权限 | 用途 | 启用方法 |
|---|---|---|
| **屏幕录制** | 通过 ScreenCaptureKit 捕获系统音频 | 系统设置 > 隐私与安全性 > 屏幕录制 > 启用 OST |
| **语音识别** | SFSpeechRecognizer 访问权限 | 系统设置 > 隐私与安全性 > 语音识别 > 启用 OST |

> 授予权限后，可能需要重新启动 OST 才能使更改生效。

### 第 2 步：启用 Siri 和听写

语音识别（尤其是服务器端）需要启用 Siri 和听写：

1. 打开 **系统设置 > Siri 与聚焦**
2. 开启 **Siri**（或"聆听..."）
3. 如果仅使用设备端识别，则无需激活 Siri——但必须下载语音模型（参见第 3 步）

### 第 3 步：下载设备端语音模型（推荐）

获得更快、离线可用且更可靠的识别：

1. 打开 **系统设置 > 通用 > 键盘 > 听写**
2. 在 **语言** 下载源语言的语音模型（如：英语、韩语、日语）
3. 下载完成后，在 OST 设置 > 语言标签页中启用 **"设备端识别"**

> 如果没有设备端模型，将使用服务器端识别。这需要互联网连接，延迟可能较高。

### 第 4 步：下载翻译语言包（推荐）

使用 Apple Translation 框架进行离线翻译：

1. 打开 **系统设置 > 通用 > 语言与地区 > 翻译语言**
2. 下载所需的语言对（如：英语 ↔ 中文）

> 没有翻译语言包，离线翻译将无法使用。

## 构建

```bash
# 克隆仓库
git clone https://github.com/9bow/OST.git
cd OST

# 完整构建 → 生成 build/OST.app
./build.sh

# 仅类型检查（无二进制文件）
./build.sh --typecheck

# 清理构建
./build.sh --clean

# 运行
open build/OST.app
```

无需 Xcode 项目。构建脚本通过 `xcrun swiftc` 编译所有 Swift 源代码。

> 如果 macOS 在首次运行时阻止应用，请执行：
> ```bash
> xattr -dr com.apple.quarantine build/OST.app
> ```

## 使用方法

### 开始会话

1. 点击菜单栏中的 **字幕图标**
2. 选择源语言和目标语言（或使用"Auto"进行自动检测）
3. 点击 **Start** 开始捕获系统音频
4. 叠加窗口将显示实时语音识别和翻译

### 叠加层控制

| 操作 | 方法 |
|---|---|
| **锁定/解锁** | 菜单栏 > Lock Overlay，或 设置 > 显示 > 叠加窗口 |
| **移动** | 解锁后拖动叠加窗口 |
| **调整大小** | 解锁后拖动窗口边缘 |
| **滚动** | 解锁后滚动字幕历史 |
| **重置位置** | 设置 > 显示 > "Reset All Overlay Windows" |

- **锁定模式**：叠加层允许点击穿透——可以正常与后面的窗口交互
- **解锁模式**：拖动移动，拖动边缘调整大小，滚动字幕历史。自动滚动到最新文本

### 显示模式

在 **设置 > 显示 > 模式** 中配置：

- **合并**：在单个窗口中显示原文和译文
- **分离**：将识别（原文）和翻译分为两个独立窗口。每个窗口可独立放置和调整大小。锁定/解锁同时应用于两个窗口

### 提示

- **语音停顿**：在 设置 > 显示 > "Speech Pause" 滑块中调整。较短的值更快确定文本；较长的值等待自然句子结束
- **字幕过期**：旧字幕在设定时间后自动消失（默认 10 秒）
- **最大行数**：控制同时显示的字幕条目数
- **会话历史**：通过菜单栏 > Session History 查看过去的语音识别会话。可导出会话记录

## 架构

```
ScreenCaptureKit (16kHz mono) → SpeechRecognizer → AppState → TranslationService → Overlay Views
     SystemAudioCapture              SFSpeech          entries      Translation.framework     NSPanel
```

### 源代码结构

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

## 故障排除

| 问题 | 解决方法 |
|---|---|
| 未捕获到音频 | 在系统设置中授予屏幕录制权限，然后重新启动 OST |
| 语音识别不工作 | 授予语音识别权限；确保已启用 Siri 和听写 |
| 翻译未显示 | 在系统设置 > 翻译语言中下载翻译语言包 |
| 叠加层不可见但阻止点击 | 使用 设置 > 显示 > "Reset All Overlay Windows" 恢复默认位置 |
| macOS 阻止应用运行 | 运行 `xattr -dr com.apple.quarantine build/OST.app` |
| 设备端识别无结果 | 在系统设置 > 键盘 > 听写中下载对应语言的语音模型 |

## 已知问题

- **端点检测（EPD）** — 语音分割使用停顿计时器结合句子边界检测，而非正式的端点检测。字幕边界有时可能在句子中间分割或将不相关的短语合并。
- **自动语言检测** — 自动检测对前约 15 个字符使用 NLLanguageRecognizer，对于短或模糊的输入可能误判语言。每个会话仅检测一次。
- **翻译一致性** — 翻译按语音片段触发。短或碎片化的片段可能产生不太连贯的翻译。
- **语音识别重启间隔** — SFSpeechRecognizer 的识别任务在约 60 秒后过期并自动重启。重叠检测可最大限度减少重复文本，但仍可能出现短暂的识别间隔。

## 许可证

[MIT](LICENSE)
