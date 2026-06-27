# 开发日志（DEVLOG）

每次 Agent / 人工开发收尾时**追加**一节（ newest on top 或 bottom 统一一种；本文件约定：**新条目写在最上方**）。

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

- 登录自启、System Voice

---

## 2026-06-27（macOS Sonus Companion MVP）

### Done
- 全局热键默认 **⌥Esc**（Carbon）；Settings 可录制修改
- 选中文本：Accessibility `kAXSelectedTextAttribute` → 剪贴板 Cmd+C fallback（可关闭，恢复剪贴板）
- HTTP 客户端对接现有 **`GET /health`、`GET /voices`、`POST /tts`**（默认 `http://127.0.0.1:8000`）
- `AVAudioPlayer` 播放 + 本地 WAV 缓存（`~/Library/Caches/SonusCompanion/audio/`）
- Settings：Server URL、Voice、Speed、热键、缓存、Accessibility 引导
- 日志：`~/Library/Logs/SonusCompanion/sonus-companion.log`
- Phase 2 stub：`SonusSystemVoiceInstaller` + [SYSTEM_VOICE_RESEARCH.md](SYSTEM_VOICE_RESEARCH.md)
- `xcodebuild` Debug **BUILD SUCCEEDED**

### Changed Files

- `SonusCompanion/**`（新建 Xcode 工程与 Swift 源码）
- `SonusCompanion/CHANGELOG.md`、`SonusCompanion/README.md`
- `docs/COMPANION.md`、`docs/SYSTEM_VOICE_RESEARCH.md`（新建）
- `docs/ROADMAP.md`、`docs/DEVLOG.md`

### Current Status

- Companion 与 Python 后端 API 对齐（端口 8000，路径 `/tts`）
- Launch at Login、System Voice 安装：仅占位 UI
- 播放中改 speed 仅影响下次播放（MVP 简化）

### Next

- 真机验收：MarginNote / Safari / Preview + Accessibility 权限
- Companion 流式播放（`/tts/stream`）
- System Voice Audio Unit Extension

---

### Done

- README「Docker」小节补充 **macOS + Colima** 与 **`brew services start colima`** 说明（与 `restart: unless-stopped` 的关系）  

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
