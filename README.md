# Sonus

通用本地 **TTS（Text-to-Speech）** 服务：调用方只依赖稳定的 HTTP API，与底层声学模型解耦。第一阶段默认使用 **Kokoro（kokoro-onnx + ONNX Runtime）**，针对 Apple Silicon 本地开发友好。

## 文档与 Agent 上下文

| 文件 | 用途 |
|------|------|
| [AGENTS.md](AGENTS.md) | 给 Codex / Cursor Agent 的规则、必读顺序、构建命令 |
| [docs/PRODUCT.md](docs/PRODUCT.md) | 产品目标、MVP、非目标、场景 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 模块划分、数据流、如何接新引擎 |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 进度与下一优先级 |
| [docs/DECISIONS.md](docs/DECISIONS.md) | 技术决策（轻量 ADR） |
| [docs/DEVLOG.md](docs/DEVLOG.md) | 每次开发后的状态记录（**新条目写在文件顶部**） |
| [SonusCompanion/README.md](SonusCompanion/README.md) | macOS 菜单栏 Companion 构建与用法 |
| [docs/COMPANION.md](docs/COMPANION.md) | Companion 架构与 API 适配 |

人类读者从本 README 入门即可；**让 Agent 改代码前**，请其先读 `AGENTS.md` 与上述 `docs/` 全文。

## 功能（MVP）

- `POST /tts`：JSON 入参，返回 `audio/wav` 或 `audio/mpeg`
- `POST /tts/stream`：JSON 入参，**chunked** 返回 `audio/L16`（16-bit mono PCM，24 kHz）
- `POST /v1/audio/speech`：**OpenAI 兼容** TTS（Hermes / OpenAI SDK 可直接对接）
- `GET /health`：存活检查
- `GET /voices`：逻辑音色（稳定）与当前引擎原生音色列表
- CLI：`sonus serve`、`sonus tts`（本地直跑引擎，不经过 HTTP）

## 环境

- Python **3.12+**
- [uv](https://docs.astral.sh/uv/) 推荐
- **MP3** 输出依赖系统安装 **ffmpeg**（`pydub` 转码）；仅 WAV 可不装 ffmpeg

## 安装

```bash
cd /Users/wujie/Workspace/Sonus
uv sync
```

## 模型文件

Sonus 使用 **两套 Kokoro 资源**（英文等多语走 v1.0；**中文必须走 v1.1-zh + misaki**，否则发音会严重失真）：

### v1.0（英文 / 日文等）

在项目根 `models/` 下：

- [kokoro-v1.0.onnx](https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx)
- [voices-v1.0.bin](https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin)

### v1.1 中文（`zh_female` / `zh_male` 必需）

- [kokoro-v1.1-zh.onnx](https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.1-zh.onnx)
- [voices-v1.1-zh.bin](https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.1-zh.bin)
- [kokoro-v1.1-zh-config.json](https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh/raw/main/config.json) → 保存为 `models/kokoro-v1.1-zh-config.json`

示例：

```bash
mkdir -p models
curl -L -o models/kokoro-v1.0.onnx \
  https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
curl -L -o models/voices-v1.0.bin \
  https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
curl -L -o models/kokoro-v1.1-zh.onnx \
  https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.1-zh.onnx
curl -L -o models/voices-v1.1-zh.bin \
  https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.1-zh.bin
curl -L -o models/kokoro-v1.1-zh-config.json \
  https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh/raw/main/config.json
```

**中文测试建议**：纯中文与**中英混排**（如「你好，这是 Sonus 测试。」）均可；混排依赖 misaki `en_callable`（默认开启，见 `SONUS_ZH_EN_MIXED`）。关闭混排或极个别英文专名仍怪时，可改成「索纳斯」。

## 配置（环境变量，前缀 `SONUS_`）

| 变量 | 含义 | 默认 |
|------|------|------|
| `SONUS_HOST` | HTTP 绑定地址 | `127.0.0.1` |
| `SONUS_PORT` | HTTP 端口 | `8000` |
| `SONUS_ENGINE` | 引擎 id（`kokoro` / `qwen3-tts`；可运行中 `PUT /engines/active` 切换） | `kokoro` |
| `SONUS_LOG_LEVEL` | 日志级别 | `info`（可选 `debug` / `warning` / `error` / `critical`） |
| `SONUS_MAX_CHUNK_CHARS` | 长文本切分上限（字符）；`0` 关闭 | `280` |
| `SONUS_CACHE_ENABLED` | 是否启用磁盘音频缓存 | `true` |
| `SONUS_CACHE_DIR` | 缓存目录 | `.cache/sonus` |
| `SONUS_CACHE_TTL_SECONDS` | 缓存过期秒数；`0` 永不过期 | `0` |
| `SONUS_MODEL_PATH` | Kokoro v1.0 ONNX 路径 | `models/kokoro-v1.0.onnx` |
| `SONUS_VOICES_PATH` | Kokoro v1.0 voices 路径 | `models/voices-v1.0.bin` |
| `SONUS_ZH_MODEL_PATH` | Kokoro v1.1 中文 ONNX | `models/kokoro-v1.1-zh.onnx` |
| `SONUS_ZH_VOICES_PATH` | Kokoro v1.1 中文 voices | `models/voices-v1.1-zh.bin` |
| `SONUS_ZH_VOCAB_CONFIG_PATH` | v1.1 中文 config.json | `models/kokoro-v1.1-zh-config.json` |
| `SONUS_ZH_EN_MIXED` | 中文句内英文片段走 espeak G2P（`en_callable`） | `true` |
| `SONUS_QWEN3_MODEL_DIR` | Qwen3-TTS HF 快照目录 | `models/qwen3-tts`（或 `{SONUS_MODELS_DIR}/qwen3-tts`） |

可选：在项目根放置 `.env`（已被 `pydantic-settings` 读取）。

### Qwen3-TTS（可选第二引擎）

```bash
# 安装可选依赖（含 PyTorch + qwen-tts）
uv sync --extra qwen

# 下载 0.6B CustomVoice 权重（约 1.7GB）
./scripts/download-qwen3-model.sh

# 启动并切换
uv run --extra qwen sonus serve
curl -sS http://127.0.0.1:8000/engines
curl -sS -X PUT http://127.0.0.1:8000/engines/active \
  -H 'Content-Type: application/json' \
  -d '{"engine":"qwen3-tts"}'
```

Companion Settings → **Engine** 可在运行时切换；冷启动默认引擎由 `SONUS_ENGINE` / UserDefaults 决定。

## 启动服务

```bash
uv run sonus serve
# 调试日志
uv run sonus serve --log-level debug
# 或
uv run uvicorn sonus.app:app --host 127.0.0.1 --port 8000
```

HTTP 响应头 **`X-Request-ID`**：可传入自定义 id 便于串联日志；未传则服务端生成 UUID。日志行格式：`[req=<id>]`。

## API

### `POST /tts`

请求体（`format` 可选，默认 `wav`）：

```json
{
  "text": "需要朗读的内容",
  "voice": "zh_female",
  "speed": 1.0,
  "format": "wav"
}
```

- **voice**：逻辑音色（如 `zh_female`）或 Kokoro 原生 id（如 `zf_xiaoxiao`）。未知原生音色会返回 400。
- **speed**：`0.5`–`2.0`（与 Kokoro 约束一致）。
- **format**：`wav` | `mp3`。
- **长文本**：超过 `SONUS_MAX_CHUNK_CHARS`（默认 280 字）时自动按段落/句号等切分，分段合成后拼接为一条音频（客户端无感）。
- **缓存**：相同 `text + voice + speed + format`（及引擎、切分配置）会写入 `.cache/sonus/`；响应头 **`X-Cache: hit|miss|disabled`**。流式 `/tts/stream` 单独缓存 PCM。

响应：`audio/wav` 或 `audio/mpeg` 二进制流。

示例：

```bash
curl -sS -X POST "http://127.0.0.1:8000/tts" \
  -H "Content-Type: application/json" \
  -d '{"text":"你好，Sonus。","voice":"zh_female","speed":1.0,"format":"wav"}' \
  --output out.wav
```

### `POST /tts/stream`

请求体（无 `format` 字段，固定 PCM 流）：

```json
{
  "text": "需要朗读的内容",
  "voice": "zh_female",
  "speed": 1.0
}
```

响应：**HTTP chunked**，`Content-Type: audio/L16; rate=24000; channels=1`（16-bit 小端 mono PCM）。  
响应头：

- `X-Audio-Sample-Rate`: `24000`
- `X-Audio-Format`: `pcm_s16le`

客户端需按 chunk 拼接 PCM 后自行播放或封装为 WAV。长文本同样会先切分再逐段流出。

示例（保存原始 PCM）：

```bash
curl -sS -N -X POST "http://127.0.0.1:8000/tts/stream" \
  -H "Content-Type: application/json" \
  -d '{"text":"你好，流式测试。","voice":"zh_female","speed":1.0}' \
  --output out.pcm
```

用 ffplay 试听（24 kHz mono s16le）：

```bash
ffplay -f s16le -ar 24000 -ac 1 out.pcm
```

### `POST /v1/audio/speech`（OpenAI 兼容）

与 [OpenAI Audio Speech API](https://platform.openai.com/docs/api-reference/audio/createSpeech) 字段对齐，便于 Hermes 等框架将 `base_url` 指向本地 Sonus。

请求体：

```json
{
  "model": "tts-1",
  "input": "Hello, world!",
  "voice": "alloy",
  "response_format": "mp3",
  "speed": 1.0
}
```

- **model**：必填，接受任意字符串（如 `tts-1`、`gpt-4o-mini-tts`）；当前不用于路由，仅写日志。
- **input**：待合成文本（最长 4096 字符）。
- **voice**：OpenAI 内置名（`alloy`、`nova`、`shimmer` 等）或 Sonus 逻辑音色（`zh_female`、`en_male` 等）。
- **response_format**：`mp3`（默认）| `wav` | `pcm`；`opus` / `aac` / `flac` 暂不支持（422）。
- **speed**：`0.25`–`4.0`，默认 `1.0`。
- **instructions**：可选，当前忽略。

OpenAI voice 与 Sonus 逻辑音色映射示例：`alloy` / `nova` → `en_female`，`echo` / `onyx` → `en_male`。中文请直接用 **`zh_female`** / **`zh_male`**。

响应：二进制音频（`audio/mpeg`、`audio/wav` 或 raw PCM）；同样有 **`X-Cache`** 头。

示例（OpenAI SDK 风格 curl）：

```bash
curl -sS -X POST "http://127.0.0.1:8000/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{"model":"tts-1","input":"你好，Sonus。","voice":"zh_female","response_format":"wav"}' \
  --output openai.wav
```

Python（`openai` 库，将 `base_url` 指向 Sonus）：

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:8000/v1", api_key="unused")
audio = client.audio.speech.create(
    model="tts-1",
    voice="zh_female",
    input="你好，这是 OpenAI 兼容测试。",
    response_format="wav",
)
audio.stream_to_file("out.wav")
```

## Docker（Linux 服务器 / 可选本地）

镜像**不包含**模型权重（体积大）；运行时将宿主机的 `models/` 只读挂载进容器。

**1. 准备模型**（若尚未下载）：

```bash
./scripts/download-models.sh
```

**2. 构建并启动**：

```bash
docker compose build
docker compose up -d
```

默认映射 **`http://127.0.0.1:8000`**（改端口：`SONUS_PUBLISH_PORT=9000 docker compose up -d`）。

**3. 验证**：

```bash
curl -sS http://127.0.0.1:8000/health
docker compose logs -f sonus
```

说明：

- 容器内已装 **ffmpeg**（MP3 可用）；`SONUS_HOST=0.0.0.0` 已在镜像中设置。
- 音频缓存使用命名卷 **`sonus-cache`**（非 bind mount）。
- 开发机仍推荐 **`uv run sonus serve`**（Apple Silicon 上通常比 Docker VM 更顺）。

### macOS + Colima：登录后自动起 Docker（再带起 Sonus）

`docker-compose.yml` 里 **`restart: unless-stopped`** 只会在 **Docker 引擎已在跑** 时把 Sonus 容器拉起来。若本机 Docker 指向 **Colima**（`docker context` 为 `colima`），推荐用 Homebrew 自带的登录自启（与 `brew info colima` 的说明一致）：

```bash
brew services start colima
```

- 效果：**当前用户登录后** launchd 会启动 Colima；等 VM 就绪后再访问 `http://127.0.0.1:8000/health`（首次可能多等几秒）。
- 关闭自启：`brew services stop colima`（不会卸载镜像或删掉 compose 项目）。
- 若 `brew services start colima` 后 `docker context` 不是 `colima`，可执行：`docker context use colima`。
- 说明：这是 **登录会话** 级自启；未登录桌面会话时一般不会跑虚拟机（与常见 Mac 使用方式一致）。

仅构建镜像、不用 Compose：

```bash
docker build -t sonus:local .
docker run --rm -p 8000:8000 \
  -v "$(pwd)/models:/app/models:ro" \
  -v sonus-cache:/app/.cache/sonus \
  sonus:local
```

## CLI

```bash
uv run sonus tts --text "Hello from Sonus" --voice en_female --output demo.wav
```

## 测试

```bash
uv sync --all-groups
uv run pytest
```

测试使用 **MockEngine**，不加载 ONNX 模型；覆盖 `voices` 映射、`TTSService`、HTTP API（含 `/v1/audio/speech`、`X-Request-ID`）与 schema 校验。

## 架构说明（模型无关）

- **HTTP 层**（`sonus.app`）只依赖 `TTSRequest` 与 `TTSService`。
- **业务编排**（`sonus.service`）把逻辑 `voice` 解析为引擎音色 + `lang`，再编码为 WAV/MP3。
- **引擎**（`sonus.engines.kokoro`）实现具体推理；后续可新增其它引擎并在 `sonus.factory` 中注册，**无需修改客户端**。

## 许可证

项目代码以 MIT 为宜（若与依赖冲突请再调整）；Kokoro 模型许可见上游发布页。
