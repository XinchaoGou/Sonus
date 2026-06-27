# 产品说明（PRODUCT）

## 一句话

**Sonus**：本地部署、模型可替换的通用 TTS 服务；客户端只依赖稳定 **`POST /tts`**（及辅助端点），不感知 Kokoro 或其它后端实现。

## 目标用户与场景（第一阶段）

| 场景 | 说明 |
|------|------|
| MarginNote 4 论文朗读 | 选中文本 → **Sonus Companion**（⌥Esc）或 HTTP → 播放 |
| Hermes Agent | Agent 输出 → 语音播报 |
| 飞书机器人 | 消息 → 生成音频 → 发群 |
| Python / CLI / 其它 Agent | HTTP 或 `sonus tts` |

## 核心原则（与实现对齐）

1. **API 长期稳定**：对外契约以 `schemas.TTSRequest` 与 `POST /tts` 为准；逻辑 `voice` id 与引擎原生 id 解耦。  
2. **模型与业务解耦**：引擎实现放在 `engines/`，由 `factory.build_engine` 装配。  
3. **调用方只依赖 HTTP**（或可选 CLI）；换模型不应要求改客户端。  
4. **第一阶段**：`uv` + FastAPI + Kokoro（kokoro-onnx）；**不强制 Docker**，优先本机调试与 Apple Silicon 体验。  
5. **后续**：Phase 2 多引擎、配置 UI 等见 [ROADMAP.md](ROADMAP.md)。

## MVP 范围（当前已实现）

- `POST /tts`：`text`、`voice`、`speed`、`format`（`wav` | `mp3`）  
- `POST /v1/audio/speech`：OpenAI 兼容（`input`、`model`、`voice`、`response_format`）  
- `GET /health`、`GET /voices`（逻辑音色 + 原生音色列表）  
- CLI：`sonus serve`、`sonus tts`  
- 配置：`SONUS_*` 环境变量 + 可选根目录 `.env`  
- 逻辑音色：`zh_female`、`zh_male`、`en_female`、`en_male`、`ja_female`（映射见 `voices.py`）

## 非目标（第一阶段不做）

- 声音克隆（Voice Clone）  
- ASR、说话人分离、实时语音助手、多人会议  
- 完整 Voice Platform（可作为远期方向）

## 技术选型（阶段一）

- **模型**：Kokoro + **kokoro-onnx**（体积小、M 系列友好、中文可用、易封装服务）  
- **暂不纳入第一阶段主路径**：XTTS-v2、Qwen3-TTS、Piper（保留为未来引擎候选）

## 依赖说明（产品侧）

- **MP3**：依赖系统 **ffmpeg**（经 pydub）；仅 WAV 可不装。  
- **模型文件**：需用户自行下载至 `models/`（见 README），不入库。
