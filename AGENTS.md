# AGENTS.md

面向 Codex / Cursor Agent 的**项目级规则**。开始改代码前请先读下列文件（按顺序）。

## Project

**Sonus**：长期维护的**通用本地 TTS 服务**。调用方只依赖稳定 HTTP API；底层声学模型可替换（当前默认 Kokoro / kokoro-onnx）。第一阶段优先 Apple Silicon 本地开发与低延迟 MVP。

## Read First

1. [README.md](README.md) — 安装、环境变量、API 与 CLI 用法  
2. [docs/PRODUCT.md](docs/PRODUCT.md) — 产品目标、MVP、非目标  
3. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 模块边界与扩展方式  
4. [docs/ROADMAP.md](docs/ROADMAP.md) — 当前进度与下一优先级  
5. [docs/DEVLOG.md](docs/DEVLOG.md) — 最近一次开发后的状态  

依赖或架构取舍见 [docs/DECISIONS.md](docs/DECISIONS.md)。

## Rules

- **最小改动**：不重构无关文件；不为了「未来可能」过度抽象。  
- **先计划后动手**：对多文件或行为变更，先用简短条目说明计划再改代码。  
- **收尾必写文档**：每次任务结束追加 `docs/DEVLOG.md`；若优先级或范围变化，同步 `docs/ROADMAP.md`。  
- **新依赖**：必须追加 `docs/DECISIONS.md`（编号 + 原因 + 取舍）。  
- **核心架构变更**：先改 `docs/ARCHITECTURE.md` 再动代码（或同一 PR 内一起更新）。  
- **可本地运行**：合并前功能应能在本仓库 `uv sync` + 模型文件就绪下跑通。  
- **数据与安全**：勿删除用户 `models/`、`.env` 或历史文档；勿提交密钥与大型二进制到 git（模型见 `.gitignore`）。

## Build / Test

```bash
cd /path/to/Sonus
uv sync
```

**HTTP 服务**（需 `models/kokoro-v1.0.onnx` 与 `models/voices-v1.0.bin`）：

```bash
uv run sonus serve
# 或
uv run uvicorn sonus.app:app --host 127.0.0.1 --port 8000
```

**CLI（不经 HTTP）**：

```bash
uv run sonus tts --text "测试" --voice zh_female --output /tmp/out.wav
```

**快速 HTTP 检查**（服务已启动时）：

```bash
curl -sS http://127.0.0.1:8000/health
curl -sS http://127.0.0.1:8000/voices | head -c 500
```

**自动化测试**（无需模型文件，使用 mock 引擎）：

```bash
cd /path/to/Sonus
uv sync --all-groups
uv run pytest
```

手动回归（可选，需 `models/` 就绪）：`serve` + `curl POST /tts` 与 `sonus tts`。

**Docker**（需本机 Docker；模型先 `./scripts/download-models.sh`）：

```bash
docker compose build && docker compose up -d
curl -sS http://127.0.0.1:8000/health
```

**SonusCompanion（macOS 菜单栏 App）**：

```bash
cd SonusCompanion
xcodebuild -scheme SonusCompanion -destination 'platform=macOS' build test
```

- **验证后收尾**（必做）：编译/运行/测试完成后  
  1. **退出 App**（`killall Sonus` 或等价方式），不要留在后台。  
  2. **删除本次调试产物**，避免 Finder / Spotlight 里出现多份同名 `Sonus.app`：  
     ```bash
     killall Sonus 2>/dev/null || true
     rm -rf ~/Library/Developer/Xcode/DerivedData/SonusCompanion-*
     rm -rf SonusCompanion/build
     ```  
     若用了自定义 `-derivedDataPath`，同样 `rm -rf` 该目录。  
- **勿安装到 `/Applications`**：不要 `cp`/`ditto`/`open` 安装到 Applications，也不要把 `.app` 复制到 Desktop、Downloads 等用户目录。用户日常安装自行从 [GitHub Releases](https://github.com/XinchaoGou/Sonus/releases) 拉最新版。  
- **本地 release 包**（仅 CI/发版需要时）：`./build_app.sh release [version]` → `build/Sonus-macos.zip`；打包完成后同样清理 `SonusCompanion/build/`，不要自动安装 zip 里的 App。

## 协作提示（给用户复制）

先阅读 README.md、AGENTS.md、docs/PRODUCT.md、docs/ARCHITECTURE.md、docs/ROADMAP.md、docs/DEVLOG.md。  
按 ROADMAP 选最高优先级任务；开发前给出简短计划；不修改无关文件。  
完成后：运行上述构建/验证命令；更新 docs/DEVLOG.md 与 docs/ROADMAP.md；若有架构或依赖变化更新 docs/DECISIONS.md；最后总结改动、风险与下一步。
