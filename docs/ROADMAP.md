# 路线图（ROADMAP）

## 当前状态（Phase 1 MVP + Companion）

已完成并可交付：

- [x] 稳定 **`POST /tts`**（WAV / MP3）  
- [x] **`GET /health`**、**`GET /voices`**  
- [x] Kokoro 引擎封装 + 逻辑音色  
- [x] **`uv` + FastAPI**，无 Docker 强制  
- [x] CLI：`sonus serve`、`sonus tts`  
- [x] Agent 文档：`AGENTS.md`、`docs/*`  
- [x] **运维友好**：可配置 `SONUS_LOG_LEVEL`、启动日志、HTTP `X-Request-ID` 与访问日志  
- [x] **自动化测试**：pytest + MockEngine（`voices` / `TTSService` / API / schema）  
- [x] **Docker / Compose** 部署（模型卷挂载 + 缓存卷）  
- [x] **OpenAI-compatible Audio API**：`POST /v1/audio/speech`  
- [x] **macOS Sonus Companion**（菜单栏 App：`SonusCompanion/`，对接 `/tts` @ `:8000`）  

## 下一优先级（建议顺序）

1. ~~**自动化测试**~~（已完成）  
2. ~~**长文本**~~（已完成：按字符切分 + 多段合成拼接）  
3. ~~**运维友好**~~（已完成）  
4. ~~**Streaming TTS**~~（已完成：`POST /tts/stream` chunked PCM）  
5. ~~**音频缓存**~~（已完成：磁盘 hash 缓存 + `X-Cache` + TTL 可选）  
6. ~~**OpenAI-compatible Audio API**~~（已完成）  
7. ~~**Docker / Compose**~~（已完成：`Dockerfile` + `docker-compose.yml` + `scripts/download-models.sh`）  
8. ~~**macOS Companion MVP**~~（已完成：`SonusCompanion/` 菜单栏 App，见 [COMPANION.md](COMPANION.md)）  
9. ~~**Companion 流式播放**~~（已完成：`POST /tts/stream` + `StreamingAudioPlayer`）  
10. **Companion 其它增强**：登录自启、System Voice（见 [SYSTEM_VOICE_RESEARCH.md](SYSTEM_VOICE_RESEARCH.md)）  
11. **配置中心 / 多音色管理 UI**：视产品需要再开。

## Phase 2 候选（来自产品规划）

- **System Voice**：`AVSpeechSynthesisProvider*` Audio Unit Extension（调研见 [SYSTEM_VOICE_RESEARCH.md](SYSTEM_VOICE_RESEARCH.md)）  
- 多引擎运行时切换或 A/B（仍保持客户端 API 稳定）  
- 更高质量模型评估（Qwen3-TTS、XTTS-v2 等）— 每引入一引擎一条 `DECISIONS` 记录  

## 明确暂不排期

- 声音克隆、ASR、会议场景（见 [PRODUCT.md](PRODUCT.md) 非目标）
