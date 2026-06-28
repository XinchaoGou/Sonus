# 技术决策（DECISIONS）

轻量 ADR：只记**为什么**，不写实现细节流水账。新决策追加表格或新章节并递增编号。

## 索引

| ID | 标题 | 状态 |
|----|------|------|
| 001 | 使用 uv 管理依赖与运行环境 | 生效 |
| 002 | 第一阶段默认引擎 Kokoro + kokoro-onnx | 生效 |
| 003 | 第一阶段不强制 Docker | 生效 |
| 004 | 逻辑音色与引擎原生 id 解耦 | 生效 |
| 005 | MP3 经 pydub + 系统 ffmpeg | 生效 |
| 006 | 维护 AGENTS.md + docs 作为 Agent 上下文 | 生效 |
| 007 | 中文使用 v1.1-zh 模型 + misaki G2P | 生效 |
| 008 | pytest + httpx 作为 dev 测试栈 | 生效 |
| 009 | 长文本在 TTSService 层按字符切分再拼接 | 生效 |
| 010 | Streaming 走 POST /tts/stream（chunked PCM） | 生效 |
| 011 | 磁盘音频缓存（hash key + 可选 TTL） | 生效 |
| 012 | Docker 多阶段镜像 + Compose | 生效 |
| 013 | OpenAI /v1/audio/speech 兼容层 | 生效 |
| 014 | 中英混排：ZHG2P + EspeakG2P en_callable | 生效 |
| 015 | Companion Text Rules：预处理在客户端执行 | 生效 |

---

## 001 — 使用 uv

**上下文**：需要可复现、快速的本地安装，且与「后续 Linux / CI」一致。  
**决策**：采用 **uv** 作为唯一推荐的包管理与 `uv run` 入口。  
**后果**：贡献者需安装 uv；`pip install -e .` 仍可能可用但文档以 uv 为准。

## 002 — Kokoro + kokoro-onnx 为默认引擎

**上下文**：首阶段要 Apple Silicon 友好、小体积、推理快、中文可用、易封装 HTTP。  
**决策**：默认 **`SONUS_ENGINE=kokoro`**，推理走 **kokoro-onnx** + ONNX Runtime。  
**后果**：中文 G2P 依赖 phonemizer/espeak 链路；质量与长句行为受上游模型限制。XTTS / Qwen3-TTS / Piper 不作为首阶段默认。

## 003 — 第一阶段不强制 Docker

**上下文**：优先跑通 MVP、降低本机调试成本，避免 Docker Desktop VM 在 Mac 上的额外问题。  
**决策**：开发与文档默认**裸机 / uv**；Docker 推迟到明确部署需求（见 ROADMAP）。  
**后果**：环境差异（ffmpeg 是否安装）需在 README 说明。

## 004 — 逻辑 voice id（API 稳定面）

**上下文**：换引擎时不应强迫所有客户端改音色字符串。  
**决策**：对外推荐使用 **`zh_female`** 等逻辑 id；映射集中在 **`voices.py`**；仍允许传引擎原生 id（校验存在于 `list_voices()`）。  
**后果**：新增逻辑音色需改 `voices.py` 与文档；引擎替换时可能需调整映射表。

## 005 — MP3 使用 pydub + ffmpeg

**上下文**：需返回 `audio/mpeg`；Python 侧无标准库 MP3 编码。  
**决策**：内部先写 WAV 字节，再用 **pydub** 转 MP3，依赖系统 **ffmpeg**。  
**后果**：无 ffmpeg 时 MP3 失败（503）；WAV 不依赖 ffmpeg。

## 006 — Agent 上下文文件（AGENTS + docs）

**上下文**：多轮 Agent 开发需要一致「入职材料」，避免重复猜状态。  
**决策**：维护 **AGENTS.md** 与 `docs/` 下 **PRODUCT / ARCHITECTURE / ROADMAP / DECISIONS / DEVLOG**；重大变更同步 DECISIONS / ARCHITECTURE。  
**后果**：每次 Agent 任务结束应追加 DEVLOG（约定见 AGENTS.md）。

## 007 — 中文 v1.1-zh + misaki-fork

**上下文**：v1.0 模型对中文使用 espeak `cmn` G2P，听感严重失真；kokoro-onnx 官方中文示例要求 **misaki ZHG2P + v1.1-zh 权重 + is_phonemes=True**。  
**决策**：`lang=cmn` 或 `zf_001` 类 v1.1 音色时走 **kokoro-v1.1-zh**；依赖 **`misaki-fork[zh]`**；逻辑音色映射为 `zf_001` / `zm_010`。  
**后果**：中文需额外下载约 380MB 级模型；中英各保留一套权重；中英混排句中的英文片段 G2P 仍可能不稳定。

## 008 — pytest + MockEngine 测试

**上下文**：ROADMAP 要求在不依赖 ONNX 权重的前提下做回归；CI 尚未接入。  
**决策**：dev 依赖 **pytest**、**httpx**（FastAPI `TestClient`）；`tests/` 内 **MockEngine** 覆盖 `voices`、`TTSService`、schema、HTTP（含 Request ID）。  
**后果**：`uv sync --all-groups` 才安装 dev 组；端到端音质仍靠手动 + 真实模型验证。

## 009 — 长文本切分在 TTSService

**上下文**：Kokoro 对过长 utterance 易「赶读」；phoneme 批切分对质量不如文本级切句。  
**决策**：在 **`TTSService`**（模型无关）用 **`text_split.split_text`**，默认 **`SONUS_MAX_CHUNK_CHARS=280`**，优先 `\n\n` / 句号 / 逗号 / 空格断点；多段 float32 PCM **`concatenate`** 后再编码。  
**后果**：极长请求耗时线性增加；段间无额外静音（MVP）；`0` 可关闭切分。

## 010 — Streaming `/tts/stream` 输出 PCM

**上下文**：Agent/客户端需要更低首包延迟；WAV/MP3 不适合 chunked 容器。  
**决策**：新增 **`POST /tts/stream`**（与 `/tts` 并存），输出 **`audio/L16`** chunked **pcm_s16le**；引擎层 **`synthesize_stream`**（Kokoro 用 `create_stream`）；长文仍走 `split_text`。  
**后果**：流式不支持 MP3；客户端需识别响应头并自行播放/封装；无 WebSocket（后续可加）。

## 011 — 磁盘音频缓存

**上下文**：论文/Agent 常重复朗读相同段落；重复合成浪费 CPU。  
**决策**：默认开启 **`SONUS_CACHE_ENABLED`**，目录 **`.cache/sonus/`**（可配置）；key = **sha256(engine + voice + speed + format + max_chunk_chars + text)**；`/tts` 存 wav/mp3，`/tts/stream` 存 pcm；**`SONUS_CACHE_TTL_SECONDS=0`** 表示不按时间过期。响应头 **`X-Cache`**。  
**后果**：换模型/改切分参数会 miss；缓存不入 git；无 LRU 容量上限（后续可加）。

## 012 — Docker 部署

**上下文**：需要 Linux 服务器可重复部署；镜像不宜打包数百 MB 模型。  
**决策**：**多阶段 Dockerfile**（`uv sync --frozen` + `python:3.12-slim` + **ffmpeg**）；**Compose** 挂载 **`./models:ro`** 与命名卷 **`sonus-cache`**；提供 **`scripts/download-models.sh`**。  
**后果**：Mac 开发仍优先裸机 uv；首次 `docker compose up` 前必须在宿主机准备好 `models/`。

## 013 — OpenAI Audio API 兼容

**上下文**：Hermes 等 Agent 框架默认对接 OpenAI **`POST /v1/audio/speech`**；Sonus 已有稳定 `/tts` 契约，不宜替换。  
**决策**：新增 **`POST /v1/audio/speech`**；请求字段 **`input` / `model` / `voice` / `response_format` / `speed`** 对齐 OpenAI；OpenAI 内置 voice 映射到 Sonus 逻辑音色，同时仍接受 **`zh_female`** 等逻辑 id；**`response_format`** 支持 **`mp3`（默认）/ `wav` / `pcm`**，`opus`/`aac`/`flac` 返回 422；**`instructions`** 接受但忽略；**`model`** 记录日志但不路由。  
**后果**：PCM 为 raw s16le（无 WAV 头）；与 `/tts` 共用 `TTSService` 与缓存；OpenAI speed 范围 0.25–4.0 宽于 `/tts` schema。

## 014 — 中英混排 G2P（en_callable）

**上下文**：v1.1 中文栈默认 `ZHG2P` 无 `en_callable` 时英文片段会被替换为 unk 或按中文误读（如「Sonus」）。  
**决策**：新增 **`sonus.zh_g2p`**：`ZHG2P(version="1.1", en_callable=...)`；英文段用 misaki **`EspeakG2P(en-us)`** 并 **unwrap `(phonemes, meta)` 元组**；默认 **`SONUS_ZH_EN_MIXED=true`**。未引入 `misaki[en]`（spacy/torch）以保持依赖轻量。  
**后果**：英文专名发音为 espeak 风格，略逊于完整 `en.G2P` 但可本地即用；可设 `SONUS_ZH_EN_MIXED=false` 回退旧行为。

## 015 — Companion Text Rules：预处理在客户端执行

**上下文**：论文阅读场景需在 TTS 前去掉引用编号等噪声；规则是个人化、场景化的（正则/替换），与选区捕获强绑定。  
**决策**：**文本预处理仅在 Sonus Companion 实现**；规则配置、Profile、Import/Export 均在 Companion Settings；HTTP `/tts` / `/tts/stream` **仍只接收最终 `text`**，MVP 不改 Python API。  
**后果**：CLI / Docker 调用方默认无预处理；Phase 2 可选读共享 JSON 在 `TTSService` 前复用同一 schema，Companion 保持唯一配置入口。设计见 [TEXT_RULES.md](TEXT_RULES.md)。
