# System Voice 调研（Phase 2）

> **状态**：未实现。Companion MVP 仅预留 `SonusSystemVoiceInstaller` stub 与 Settings 禁用按钮。

## 目标

让 Sonus 合成的声音出现在 macOS **系统朗读**链路中：

System Settings → Accessibility → **Spoken Content** → **System Voice**

使用户在「朗读选中内容」等系统能力中也能使用 Sonus 音色（未来 FishSpeech / CosyVoice2 等）。

## Apple 官方路径

自 macOS 14 / iOS 17 起，Apple 提供 **Speech Synthesis Provider** 扩展模型：

| 组件 | 作用 |
|------|------|
| `AVSpeechSynthesisProviderVoice` | 注册自定义 voice 元数据（名称、语言、性别等） |
| `AVSpeechSynthesisProviderAudioUnit` | Audio Unit 子类，接收 SSML/文本，输出 PCM buffer |
| **Audio Unit Extension** | 独立 extension target，由系统在 TTS 时加载 |

### 参考文档

- [Creating a custom speech synthesizer](https://developer.apple.com/documentation/avfaudio/creating_a_custom_speech_synthesizer)
- [AVSpeechSynthesisProviderVoice](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisprovidervoice)
- [AVSpeechSynthesisProviderAudioUnit](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisprovideraudiounit)
- WWDC 2023: *Extend Speech Synthesis with personal and custom voices*

## 建议工程结构（未来）

```
SonusCompanion.xcodeproj
├── SonusCompanion.app          # 主 App（安装器 / 配置 UI）
├── SonusSpeechProvider.appex   # Audio Unit Extension
│   ├── ProviderAudioUnit.swift
│   ├── VoiceRegistry.swift
│   └── Info.plist (NSExtension)
└── Shared/
    ├── SonusClient.swift       # 与主 App 共享 HTTP 调用
    └── PCMBridge.swift         # WAV/PCM → AudioUnit buffer
```

## 注册与安装流程（草案）

1. Extension 在 `Info.plist` 声明 `AudioComponents` / Speech Provider 类型  
2. 主 App 提供「Install System Voice」：  
   - 复制 extension 到 `~/Library/Audio/Plug-Ins/Components/` 或按 Apple 文档注册 provider voice  
   - 调用 API 刷新系统 voice 列表（具体 API 以文档为准，可能需要重启 `coreaudiod` 或 re-login）  
3. CLI 等价物：`sonus install-system-voice`（包装同一安装逻辑）

> **TODO**：对照最新 Xcode 模板与 entitlement 逐项核实；Apple 文档在不同 macOS 版本间有细微差异。

## Entitlements & 能力（预估）

| 项 | 说明 |
|----|------|
| App Groups 或 XPC | Extension 与主 App / 本地 Sonus 服务通信 |
| Network Client | Extension 内 HTTP 调 `127.0.0.1:8000` |
| 非 Sandbox 或 hardened runtime 例外 | 本地 socket 与调试 |
| Audio Unit entitlement | Extension 类型所需 |

## 数据路径（草案）

```
系统 TTS 请求
  → AVSpeechSynthesisProviderAudioUnit
  → SSML / plain text
  → HTTP POST /tts 或 /tts/stream (PCM)
  → 填充 AudioBufferList (PCM s16le / 24kHz 与 Sonus 对齐)
  → 系统播放 / 供 VoiceOver 等消费
```

流式场景优先对接现有 **`POST /tts/stream`**（`audio/L16` 24 kHz mono），减少延迟。

## 风险与挑战

| 风险 | 说明 |
|------|------|
| **Extension 调试困难** | AU 崩溃不易复现；需 attach to process、log 重定向 |
| **Streaming bridge** | 系统期望低延迟 PCM；HTTP 往返 + 模型推理需缓冲策略 |
| **Voice 列表刷新** | 安装后系统可能缓存旧 voice 列表，需文档化「如何强制刷新」 |
| **Sandbox** | Extension 默认沙盒；访问 localhost 与共享缓存需额外 entitlement |
| **多 voice / 多引擎** | 每个 provider voice 映射到 Sonus `voice` id，需配置同步 |
| **SSML 支持 subset** | 系统可能传入 SSML；MVP 可 strip tags 只读 plain text |
| **代码签名与分发** | Extension 必须与主 App 同 Team 签名；notarization 流程更复杂 |
| **用户预期** | 系统 TTS 与 Companion 快捷键是两条路径，行为需一致（语速、音色） |

## MVP Companion 与 System Voice 边界

| 能力 | Companion MVP | System Voice Phase 2 |
|------|---------------|----------------------|
| 触发方式 | 全局快捷键 / 菜单 | 系统朗读、VoiceOver 等 |
| 文本来源 | 当前选区 | 系统传入 SSML/text |
| 播放 | App 内 AVAudioPlayer | AU 输出 PCM 给系统 |
| 依赖 Sonus HTTP | 是 | 是（extension 内或 XPC 代理） |

## 建议实施顺序（Phase 2）

1. 用 Apple 模板创建最小 AU Extension，固定 voice，硬编码返回 sine wave（验证加载）  
2. 改为调用 `POST /tts`，整段 WAV → PCM 填 buffer  
3. 对接 `/tts/stream` 降低首包延迟  
4. 主 App 安装 UI + voice 列表同步  
5. 文档化用户安装 / 卸载步骤  

## 当前代码预留

- `SonusCompanion/SystemVoice/SonusSystemVoiceInstaller.swift` — `install()` throws `notImplemented`  
- Settings → **Install System Voice** 按钮 disabled，标注 Coming later  
