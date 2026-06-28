# 开发日志（DEVLOG）

每次 Agent / 人工开发收尾时**追加**一节（ newest on top 或 bottom 统一一种；本文件约定：**新条目写在最上方**）。

---

## 2026-06-28（Companion — App Icon + v0.2.2）

### Done

- 新增 **`Assets.xcassets` / AppIcon**；Xcode `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
- 图标生成脚本与源文件：`SonusCompanion/scripts/`（SVG + `generate_app_icon.py`）
- 版本 **0.2.2**；push tag 发版

### Changed Files

- `Assets.xcassets/**`、`project.pbxproj`、`Info.plist`
- `SonusCompanion/scripts/**`、`CHANGELOG.md`

---

## 2026-06-28（Companion — Phase C 应用内自动更新）

### Done

- 移植 updater 六模块：`UpdateConfig`、`AppVersion`、`GitHubReleaseClient`、`UpdateDownloader`、`UpdateInstaller`、`AppUpdateController`
- 半自动流程：启动/每 24h 检查、NSAlert 三按钮、安装前二次确认、shell 脚本替换 `/Applications/Sonus.app`
- Settings → **Updates** 区块；非 `/Applications` 路径提示
- `AppVersionTests`；版本升至 **0.2.1**

### Changed Files

- `SonusCompanion/Update*.swift`、`AppVersion.swift`、`AppUpdateController.swift`
- `SettingsView.swift`、`MenuBarView.swift`、`SonusCompanionApp.swift`
- `SonusCompanionTests/AppVersionTests.swift`、`project.pbxproj`
- `CHANGELOG.md`、`docs/DEVLOG.md`

### Next

- 推 **`v0.2.1`** tag 发版；从 GitHub 安装的 v0.2.0 验证升级到 v0.2.1

---

### Done

- 新增 **`.github/workflows/companion-release.yml`**：`push tags: v*` → `macos-14` 跑 `build_app.sh release` → 上传 **`Sonus-macos.zip`** 到 GitHub Release
- Release body 含安装步骤；注明仅含菜单栏客户端，后端见 README
- CI 内校验 zip 含 `Sonus.app/Contents/MacOS/Sonus`

### Changed Files

- `.github/workflows/companion-release.yml`
- `SonusCompanion/README.md`、`CHANGELOG.md`、`docs/DEVLOG.md`

### Next

- 推 **`v0.2.0`** tag 验证 CI（需 merge 到 GitHub 后执行）
- Phase C：客户端 updater + Settings Updates

---

## 2026-06-28（Companion — Phase A 重命名 + Release 构建）

### Done

- 产物重命名：**`Sonus.app`**（Xcode `PRODUCT_NAME`），Bundle ID **`com.sonus.app`**
- 用户数据路径统一为 `~/Library/Logs|Caches|Application Support/Sonus/`
- 新增 **`SonusCompanion/build_app.sh release [version]`**：Release build → ad-hoc 签名 → `build/Sonus-macos.zip`
- 单元测试 `@testable import Sonus`；`xcodebuild build test` 通过

### Changed Files

- `SonusCompanion.xcodeproj/project.pbxproj`、xcscheme、`Info.plist`
- `Logger.swift`、`AudioPlayer.swift`、`TextRuleStore.swift`、Tests
- `SonusCompanion/build_app.sh`、`README.md`、`CHANGELOG.md`

### Next

- Phase B：`companion-release.yml`（tag `v*` → GitHub Release）
- Phase C：客户端 updater 模块 + Settings Updates 区块

---

## 2026-06-28（Companion — Settings 窗口置前）

### Done

- 菜单栏 **Settings…** 点击后设置窗口被其他应用遮挡：新增 `SettingsWindowPresenter`，临时切换 `activationPolicy` 为 `.regular`、`activate(ignoringOtherApps:)`，并将 Settings 窗口 `makeKeyAndOrderFront`；关闭设置窗口后恢复 `.accessory`（无 Dock 图标）
- **多桌面 / Space**：为 Settings 窗口设置 `collectionBehavior.moveToActiveSpace`，移除 `orderFrontRegardless`（后者会切回旧 Space 而非把窗口移到当前桌面）

### Changed Files

- `SonusCompanion/MenuBarView.swift`、`SettingsView.swift`
- `SonusCompanion/CHANGELOG.md`、`docs/DEVLOG.md`

---

## 2026-06-28（Companion Text Rules — 移除 Plain Profile）

### Done

- 内置 Profile 精简为 **Paper Reading** + **General**（原文朗读档位）；移除重复的 **Plain**
- 加载旧配置时自动迁移：`plain` Profile 删除，若曾选中 Plain 则切到 General，并写回 JSON

### Changed Files

- `SonusCompanion/Models/TextRule.swift`、`TextRuleStore.swift`
- `SonusCompanionTests/TextRuleStoreTests.swift`、`TextPreprocessorTests.swift`
- `docs/DEVLOG.md`、`docs/TEXT_RULES.md`

---

## 2026-06-28（Companion Text Rules — Profile 切换闪退 + 删除入口）

### Done

- **Plain / General 切换闪退**：从 Paper（多条规则）切到空规则 Profile 时，`ForEach` 仍持有旧 index，`ruleEditor` 访问 `rules[ruleIndex]` 越界崩溃；改为按 `rule.id` 迭代、Rules Section 加 `.id(activeProfileId)` 强制重建、切换 Profile 时重置 `isEditingRules`
- **删除 Profile 入口**：自定义 Profile 选中时显示 **Delete Profile…** + 确认对话框；内置 Profile 不可删；`TextRuleStore.canDeleteActiveProfile` 供 UI 判断
- **Restore Built-in Defaults**：仅 Paper Profile 显示

### Changed Files

- `SonusCompanion/TextRulesSettingsView.swift`、`TextRuleStore.swift`
- `SonusCompanionTests/TextRuleStoreTests.swift`
- `docs/DEVLOG.md`

### Next

- 真机回归：Settings 内 Profile 切换；自定义 Profile 增删

---

## 2026-06-28（Companion Text Rules — Move Down 修复）

### Done

- 验证 **Move Down** off-by-one：Swift `move(toOffset:)` 向下移一位需 `index + 2`（移除后数组上的插入点），误用 `index + 1` 作为 `toOffset` 会无操作；若把 `index + 2` 当作 remove-then-insert 的目标索引则会移到末尾
- **`TextRulesSettingsView`**：Move Up/Down 改走 `moveRules`，向下时使用 `index + direction + 1` 作为 `toOffset`
- **`TextRuleStore.moveRule`**：相邻项（|Δindex|==1）用 `swapAt`，避免 remove+insert 语义混淆
- **`TextRuleStoreTests`**：补充 reorder 回归（swap / 错误 toOffset / 越界 insert）

### Changed Files

- `SonusCompanion/TextRuleStore.swift`、`TextRulesSettingsView.swift`
- `SonusCompanionTests/TextRuleStoreTests.swift`
- `docs/DEVLOG.md`

### Next

- 真机回归 Text Rules 编辑顺序

---

## 2026-06-28（Companion Text Rules — 实现）

### Done

- **`TextRule` / `TextRuleProfile` / `TextRulesDocument`**：schema v1 + 内置 Paper / Plain / General Profile
- **`TextPreprocessor`**：字面量 / 正则（含 `$1` 捕获组）、非法 pattern 跳过、规则指纹 SHA256、`noop` bypass
- **`TextRuleStore`**：JSON 持久化 `~/Library/Application Support/SonusCompanion/text-rules.json`；Import（整文件替换）/ Export；恢复 Paper 内置默认；自定义 Profile CRUD
- **`AppState.speakSelection()`**：预处理 → 空文本拦截 → 缓存 key 含 `rulesFingerprint`
- **`TextRulesSettingsView`**：Settings sheet（总开关、Profile、规则 CRUD、Move Up/Down、Preview、Use last selection）
- **菜单栏**：`Rules: On · Paper Reading` 状态 + Profile 子菜单 + 总开关 Toggle
- **`SonusCompanionTests`**：14 项 XCTest（`xcodebuild test` **TEST SUCCEEDED**）

### Changed Files

- `SonusCompanion/Models/TextRule.swift`、`TextPreprocessor.swift`、`TextRuleStore.swift`、`TextRulesSettingsView.swift`
- `SonusCompanion/AppState.swift`、`AudioPlayer.swift`、`SettingsView.swift`、`MenuBarView.swift`
- `SonusCompanionTests/**`、`project.pbxproj`、xcscheme
- `SonusCompanion/CHANGELOG.md`、`SonusCompanion/README.md`
- `docs/TEXT_RULES.md`、`docs/ROADMAP.md`、`docs/COMPANION.md`、`docs/ARCHITECTURE.md`、`docs/DEVLOG.md`

### Next

- 真机回归：MarginNote / Preview 论文选区 + 规则 Preview 微调
- 配置中心 / 多音色 UI（视产品需要）

---

## 2026-06-28（Companion Text Rules — 设计文档）

### Done

- 与产品方对齐 **10 项设计决策**（grill-me）：Companion 本地预处理、正则+捕获组、内置 Paper 预设、Profile、JSON 持久化、Preview、缓存指纹等
- 新增 **[TEXT_RULES.md](TEXT_RULES.md)**：数据流、schema、内置规则表、Settings UI、实现顺序、Phase 2 边界
- **DECISIONS 015**：预处理在客户端执行，不改 `/tts` API
- 更新 **ROADMAP**（下一优先级 #11）、**COMPANION.md**（模块与路径）

### Changed Files

- `docs/TEXT_RULES.md`（新建）
- `docs/DECISIONS.md`、`docs/ROADMAP.md`、`docs/COMPANION.md`、`docs/DEVLOG.md`

### Next

- 按 [TEXT_RULES.md](TEXT_RULES.md) 实现顺序在 `SonusCompanion/` 落地

---

## 2026-06-28（Companion bugfix：clipboard fallback）

### Done

- **`simulateCopyCommand()`**：`CGEventSource` / `CGEvent` 创建失败时返回 `false`，不再无条件报告成功
- 复核 **`WAVEncoder.wrapPCM()`** RIFF 大小：`36 + dataSize` 与 WAV 规范一致，无需改动（改为 `40 + dataSize` 反而会错 4 字节）

### Changed Files

- `SonusCompanion/SelectedTextReader.swift`
- `docs/DEVLOG.md`

---

### Done

- **`LaunchAtLoginManager`**：`SMAppService.mainApp` 注册 / 注销
- Settings → System：**Launch at Login** Toggle
- 状态 `.requiresApproval` 时提示并在 Login Items 中批准；提供「Open Login Items」按钮
- `xcodebuild` **BUILD SUCCEEDED**

### Changed Files

- `SonusCompanion/LaunchAtLoginManager.swift`（新建）
- `SonusCompanion/SettingsView.swift`、`project.pbxproj`
- `SonusCompanion/CHANGELOG.md`、`SonusCompanion/README.md`
- `docs/ROADMAP.md`、`docs/COMPANION.md`、`docs/DEVLOG.md`

### Notes

- 需有效代码签名；未签名或 ad-hoc 构建可能无法注册（Settings 会显示错误）

### Next

- 真机验收登录自启 + 流式播放
- 配置中心 / 多音色 UI（视产品需要）

---

## 2026-06-28（移除 System Voice 计划）

### Done

- 产品决定不再做 macOS System Voice（`AVSpeechSynthesisProvider*`）集成
- 删除 `docs/SYSTEM_VOICE_RESEARCH.md`、`SonusSystemVoiceInstaller` stub 与 Settings 占位按钮
- ROADMAP / COMPANION 后续项与 Phase 2 候选中移除 System Voice；列入「明确暂不排期」

### Changed Files

- 删除：`docs/SYSTEM_VOICE_RESEARCH.md`、`SonusCompanion/.../SystemVoice/SonusSystemVoiceInstaller.swift`
- `SonusCompanion/SettingsView.swift`、`project.pbxproj`
- `docs/ROADMAP.md`、`docs/COMPANION.md`、`SonusCompanion/README.md`、`SonusCompanion/CHANGELOG.md`

### Next

- ~~Companion 登录自启~~（已完成 2026-06-28）

---

## 2026-06-27（Companion 流式播放）

### Done

- **`StreamingAudioPlayer`**：`AVAudioEngine` 播放 `/tts/stream` PCM chunk（24 kHz mono s16le）
- **`SonusClient.synthesizeStream`**：URLSession 流式读取，8 KB 批次 yield
- 缓存未命中走流式；**首包到达即播放**（日志 `stream ttfb_ms`）
- 流结束后 PCM 封装 WAV 写入本地缓存（与 `/tts` 缓存 key 一致）
- 缓存命中仍走 `AVAudioPlayer` 整文件播放
- 流式播放支持 pause / resume / stop / 播放中改速
- `xcodebuild` **BUILD SUCCEEDED**

### Changed Files

- `SonusCompanion/StreamingAudioPlayer.swift`（新建）
- `SonusCompanion/SonusClient.swift`、`AppState.swift`、`Models/TTSRequest.swift`
- `SonusCompanion/CHANGELOG.md`、`docs/ROADMAP.md`、`docs/COMPANION.md`、`docs/DEVLOG.md`

### Current Status

- 非流式 `POST /tts` 仍保留在 `SonusClient.synthesize`（备用），Companion 主路径已切流式

### Next

- ~~登录自启~~（已完成 2026-06-28）

---

## 2026-06-27（macOS Sonus Companion MVP）

### Done
- 全局热键默认 **⌥Esc**（Carbon）；Settings 可录制修改
- 选中文本：Accessibility `kAXSelectedTextAttribute` → 剪贴板 Cmd+C fallback（可关闭，恢复剪贴板）
- HTTP 客户端对接现有 **`GET /health`、`GET /voices`、`POST /tts`**（默认 `http://127.0.0.1:8000`）
- `AVAudioPlayer` 播放 + 本地 WAV 缓存（`~/Library/Caches/SonusCompanion/audio/`）
- Settings：Server URL、Voice、Speed、热键、缓存、Accessibility 引导
- 日志：`~/Library/Logs/SonusCompanion/sonus-companion.log`
- ~~Phase 2 stub：`SonusSystemVoiceInstaller`~~（后于 2026-06-28 移除，不再做 System Voice）
- `xcodebuild` Debug **BUILD SUCCEEDED**

### Changed Files

- `SonusCompanion/**`（新建 Xcode 工程与 Swift 源码）
- `SonusCompanion/CHANGELOG.md`、`SonusCompanion/README.md`
- `docs/COMPANION.md`、`docs/ROADMAP.md`、`docs/DEVLOG.md`

### Current Status

- Companion 与 Python 后端 API 对齐（端口 8000，路径 `/tts`）
- Launch at Login：仅占位 UI（后于 2026-06-28 实现）
- 播放中改 speed 仅影响下次播放（MVP 简化）

### Next

- 真机验收：MarginNote / Safari / Preview + Accessibility 权限
- Companion 流式播放（`/tts/stream`）

---

## 2026-06-13（README：Colima 登录自启）

### Done  

### Changed Files

- `README.md`、`docs/DEVLOG.md`  

---

## 2026-06-13（中英混排 G2P）

### Done

- `sonus/zh_g2p.py`：`ZHG2P` + **`EspeakG2P` en_callable**；unwrap G2P 元组返回值  
- `SONUS_ZH_EN_MIXED`（默认 `true`）；`KokoroEngine` / factory 接入  
- 测试 69 passed（含混排 phoneme 断言）  

### Changed Files

- `src/sonus/zh_g2p.py`（新建）、`engines/kokoro.py`、`config.py`、`factory.py`  
- `tests/test_zh_g2p.py`（新建）  
- `README.md`、`.env.example`、`docs/*`  

### Current Status

- 英文段为 espeak 风格；未引入 `misaki[en]`（无 torch/spacy）  
- 极个别专名仍可能不准，可音译或 `SONUS_ZH_EN_MIXED=false`  

### Next

- 可选 CI workflow  

---

## 2026-06-13（OpenAI Audio API）

### Done

- **`POST /v1/audio/speech`**：OpenAI 兼容 TTS 端点  
- `openai_compat.py`：请求 schema、OpenAI voice → 逻辑音色映射  
- 支持 **`response_format`**：`mp3`（默认）、`wav`、`pcm`；`opus`/`aac`/`flac` → 422  
- 仍可直接传 Sonus 逻辑音色（如 **`zh_female`**）  
- `TTSService` / `encode_audio` 扩展 **pcm** 输出  
- 测试 62 passed（`test_openai_api`、`test_openai_compat`）  

### Changed Files

- `src/sonus/openai_compat.py`（新建）、`app.py`、`service.py`、`audio_encode.py`  
- `tests/test_openai_api.py`、`tests/test_openai_compat.py`（新建）  
- `README.md`、`docs/ROADMAP.md`、`docs/ARCHITECTURE.md`、`docs/DECISIONS.md`  

### Current Status

- Phase 1 ROADMAP 主项已全部完成  
- `instructions` 字段暂未实现语义  

### Next

- CI workflow（可选）  
- 配置中心 / 多音色 UI（视产品需要）  

---

## 2026-06-13（Docker / Compose）

### Done

- `Dockerfile`：uv 多阶段构建，运行时含 ffmpeg，healthcheck  
- `docker-compose.yml`：8000 端口、`models` 只读挂载、缓存命名卷  
- `scripts/download-models.sh`、`.dockerignore`、`.env.example`  
- README / AGENTS / ROADMAP / DECISIONS 012  

### Changed Files

- `Dockerfile`、`docker-compose.yml`、`scripts/download-models.sh`（新建）  
- `.dockerignore`、`.env.example`  
- `README.md`、`AGENTS.md`、`docs/ROADMAP.md`、`docs/DECISIONS.md`、`docs/DEVLOG.md`  

### Current Status

- CI 未在本环境执行 `docker build`（无 docker CLI）；文件按 uv 官方模式编写，需在装有 Docker 的机器验证  

### Next

- OpenAI 兼容 Audio API  

---

## 2026-06-13（音频缓存）

### Done

- `AudioCache`：sha256 文件缓存，默认 `.cache/sonus/`  
- 配置：`SONUS_CACHE_ENABLED`、`SONUS_CACHE_DIR`、`SONUS_CACHE_TTL_SECONDS`  
- `/tts` 与 `/tts/stream` 均支持；响应头 **`X-Cache: hit|miss|disabled`**  
- `factory.build_tts_service` 统一装配  
- 测试 50 passed  

### Changed Files

- `src/sonus/cache.py`（新建）、`service.py`、`config.py`、`factory.py`、`app.py`、`cli.py`  
- `tests/test_cache.py`、`test_service.py`、`test_stream_service.py`  
- `.gitignore`、`README.md`、`docs/*`  

### Current Status

- 无 LRU / 容量上限；引擎升级后旧缓存需手动清目录  

### Next

- OpenAI 兼容 Audio API  

---

## 2026-06-13（Streaming TTS）

### Done

- **`POST /tts/stream`**：chunked **16-bit PCM**（24 kHz mono）  
- `StreamingTTSEngine` / `KokoroEngine.synthesize_stream`（`create_stream`）  
- `TTSService.synthesize_stream_pcm`；与长文本切分兼容  
- 测试 + `pytest-asyncio`；文档 DECISIONS 010  

### Changed Files

- `src/sonus/app.py`、`service.py`、`schemas.py`、`audio_encode.py`  
- `src/sonus/engines/base.py`、`engines/kokoro.py`  
- `tests/test_stream_service.py`、`test_api.py`、`test_audio_encode.py`、`conftest.py`  
- `pyproject.toml`、`README.md`、`docs/*`  

### Current Status

- 流式仅 PCM；`/tts` 仍返回完整 WAV/MP3  
- 无 WebSocket  

### Next

- OpenAI 兼容 Audio API  
- 音频缓存  

---

## 2026-06-13（长文本切分）

### Done

- `text_split.split_text`：按段落 / 句号 / 逗号 / 空格优先切分，默认 **280 字**  
- `SONUS_MAX_CHUNK_CHARS`（`0` = 不切分）  
- `TTSService` 多段合成 + PCM 拼接；日志记录 chunk 数  
- 测试：`test_text_split`、长文 mock 多段 `test_service`  

### Changed Files

- `src/sonus/text_split.py`（新建）、`service.py`、`config.py`、`app.py`、`cli.py`  
- `tests/test_text_split.py`、`tests/test_service.py`  
- `README.md`、`docs/ROADMAP.md`、`docs/ARCHITECTURE.md`、`docs/DECISIONS.md`  

### Current Status

- 长文对客户端仍是一次 `/tts` 返回一条音频  
- 段间无插入静音；中英混排仍不支持  

### Next

- Streaming TTS 或 OpenAI 兼容 API  
- 可选：段间短静音、按语言不同 chunk 上限  

---

## 2026-06-13（自动化测试）

### Done

- 引入 **pytest** + dev 组 **httpx**（`TestClient`）  
- `tests/conftest.py`：**MockEngine** fixture  
- 覆盖：`test_voices`、`test_service`、`test_schemas`、`test_logging_config`、`test_api`（33 项）  
- 更新 `AGENTS.md`、`README.md`、`DECISIONS` 008、`ROADMAP`  

### Changed Files

- `tests/*`、`pyproject.toml`  
- `docs/ROADMAP.md`、`docs/DECISIONS.md`、`docs/DEVLOG.md`  
- `AGENTS.md`、`README.md`  

### Current Status

- `uv run pytest` 全绿，无需模型文件  
- CI（GitHub Actions）未做  

### Next

- 长文本自动切分  
- 可选：CI workflow  

---

## 2026-06-13（运维日志 / Request ID）

### Done

- `SONUS_LOG_LEVEL` + CLI `--log-level`  
- 启动日志：版本、引擎、v1.0 / v1.1-zh 模型路径与 `ready=`  
- HTTP 中间件：`X-Request-ID`（可传入或自动生成）、请求耗时  
- `/tts` 合成摘要日志（voice、format、字数、字节数，不记全文）  

### Changed Files

- `src/sonus/logging_config.py`、`middleware.py`（新建）  
- `src/sonus/config.py`、`app.py`、`cli.py`  
- `README.md`、`docs/ROADMAP.md`、`docs/ARCHITECTURE.md`  

### Current Status

- ROADMAP「运维友好」项已完成  
- 下一建议：自动化测试 或 长文本切分  

### Next

- pytest + mock 引擎  
- 长文本自动切分  

---

## 2026-06-13（中文 G2P 修复）

### Done

- 中文改走 **Kokoro v1.1-zh + misaki-fork ZHG2P**（不再用 espeak `cmn`）  
- 新增 `SONUS_ZH_*` 配置项；`zh_female` → `zf_001`，`zh_male` → `zm_010`  
- 依赖：`misaki-fork[zh]`  
- README / DECISIONS 007 更新  

### Changed Files

- `src/sonus/config.py`、`engines/kokoro.py`、`factory.py`、`voices.py`  
- `pyproject.toml`、`README.md`、`docs/DECISIONS.md`  

### Current Status

- 纯中文 CLI 合成已在本机验证；英文仍走 v1.0  
- 句中夹英文（如「Sonus」）可能仍怪，建议纯中文或音译  

### Next

- 中英混排 G2P 策略（misaki en_callable）  
- pytest mock 引擎  

### Risks / Notes

- 首次中文合成会加载 jieba 词典，略慢  

---

## 2026-06-13

### Done

- 初始化 Sonus：FastAPI `POST /tts`、`GET /health`、`GET /voices`  
- Kokoro 封装（`KokoroEngine`）、`factory.build_engine`、`TTSService` 编排  
- 逻辑音色：`zh_female`、`zh_male`、`en_female`、`en_male`、`ja_female`  
- WAV / MP3 输出（MP3 依赖 ffmpeg）  
- CLI：`sonus serve`、`sonus tts`  
- 配置：`SONUS_*` + `.env`  
- 本机用已下载模型完成 CLI 与 HTTP 冒烟测试（WAV/MP3）  
- 新增 Agent 文档：`AGENTS.md`、`docs/PRODUCT.md`、`docs/ARCHITECTURE.md`、`docs/ROADMAP.md`、`docs/DECISIONS.md`、`docs/DEVLOG.md`；README 增加文档入口  

### Changed Files（本批次）

- `AGENTS.md`（新建）  
- `docs/PRODUCT.md`、`docs/ARCHITECTURE.md`、`docs/ROADMAP.md`、`docs/DECISIONS.md`、`docs/DEVLOG.md`（新建）  
- `README.md`（补充文档导航）  

### Current Status

- MVP 可用：有模型文件时 `/tts` 与 CLI 可稳定合成  
- 无自动化测试；长文本、流式、缓存、OpenAI 兼容 API、Docker 未做  

### Next（见 ROADMAP）

- pytest 最小覆盖（mock 引擎）  
- 长文本切分与拼接策略  

### Risks / Notes

- Kokoro phoneme 长度上限：极长单段可能需切分（当前未实现）  
- `pydub` 在部分环境可能对正则产生 `SyntaxWarning`（上游包，不影响功能）  
- 模型体积较大（onnx 约数百 MB 级），不入 git  
