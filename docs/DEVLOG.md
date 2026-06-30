# 开发日志（DEVLOG）

每次 Agent / 人工开发收尾时**追加**一节（ newest on top 或 bottom 统一一种；本文件约定：**新条目写在最上方**）。

---

## 2026-06-30（v0.4.4 — 孤儿后端收割 + 版本号注入修复）

### Done

- **根因（更新后仍崩，exit 1）**：in-app 更新替换 `/Applications/Sonus.app` 时，旧 App 起的 Python 后端子进程未被一起回收，继续占着 8000 端口。新 App 启动时 `BackendManager.process` 为 nil，`stopAndAwaitExit` 不动它；`waitForPortFree` 等 5s 后放弃 → spawn → `[Errno 48] address already in use`。
  - **修复**：新增 `preparePortForSpawn(port:)` = `stopAndAwaitExit` + `reapOrphanedBackends` + `waitForPortFree`。`reapOrphanedBackends` 用 `lsof -ti tcp:PORT -sTCP:LISTEN` 找占端口的 PID，按命令行含 `sonus.app:app`/`sonus-runtime` 过滤（不误杀用户其他服务），SIGTERM → 800ms → SIGKILL 清掉。
- **版本号一直停在 0.4.2**：`Info.plist` 的 `CFBundleShortVersionString` 硬编码，`GENERATE_INFOPLIST_FILE=NO` 导致 pbxproj 的 `MARKETING_VERSION` 没注入。改为 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`，版本号跟随 release tag。验证 Debug 构建 Info.plist 显示 0.4.4。

### Changed Files

- `SonusCompanion/SonusCompanion/BackendManager.swift`
- `SonusCompanion/SonusCompanion/Info.plist`
- `SonusCompanion/SonusCompanion.xcodeproj/project.pbxproj`
- `SonusCompanion/CHANGELOG.md`、`docs/DEVLOG.md`

### Verification

- `xcodebuild build` / `test`：BUILD SUCCEEDED / TEST SUCCEEDED
- Debug 产物 Info.plist：`CFBundleShortVersionString=0.4.4`
- `uv run pytest`：84 passed
- 清理 DerivedData

### Next

- 推 tag `v0.4.4` 走 CI 发版；用户在 App 内更新后真机回归切换 Qwen

---

## 2026-06-30（Qwen 切换崩溃根治 — 端口竞争 + 合成期 MPS 兜底）

### Done

- **根因 1（最频繁，exit code 1）**：`BackendManager.stopSpawnedProcess()` 调 `terminate()` 后**不等待进程退出**就立即 spawn 新 uvicorn，旧进程还没释放 8000 端口 → `[Errno 48] address already in use` → 进程秒退 → "Backend exited unexpectedly"。日志 14:10:08 / 14:57:47 两次命中。
  - **修复**：新增 `stopAndAwaitExit()`（`terminate` → `waitUntilExit`，6s 超时升级 SIGKILL）+ `waitForPortFree()`（TCP 探测端口释放，5s 超时）；`restart()` / `runEmbeddedStartup()` 在 spawn 前 `await` 这两步。
- **根因 2（合成期 MPS 崩溃）**：`Qwen3TTSEngine._ensure_loaded` 只在 `from_pretrained` 失败时回退 CPU；`generate_custom_voice` 在 MPS 上 OOM / allocator 报错时直接抛出，没有 CPU 重试。
  - **修复**：`synthesize` 捕获 MPS 运行期异常 → `_reload_on_cpu()` 重载 CPU 重试一次；新增 `SONUS_QWEN_DEVICE` 环境变量（`cpu`/`mps`/`cuda`/`auto`）让用户一键强制 CPU 绕开 MPS 不稳定。
- **根因 3（unload 释放不彻底）**：`unload` 只置 None + gc，未把模型移回 CPU、未 `mps.synchronize`，热切换时 MPS 显存残留。
  - **修复**：`unload` 先 `model.to("cpu")`（best-effort）再置 None，`torch.mps.synchronize()` + `empty_cache()`；`_device` 一并复位。
- **测试**：`tests/test_qwen_engine_stability.py` 新增合成期 MPS→CPU 回退、`SONUS_QWEN_DEVICE` 覆盖用例；两个 switch 用例 patch `_check_optional_dependency` 使其不再依赖 `qwen-tts` extra 是否安装。

### Changed Files

- `SonusCompanion/SonusCompanion/BackendManager.swift`
- `src/sonus/engines/qwen3_tts.py`
- `tests/test_qwen_engine_stability.py`
- `docs/DEVLOG.md`

### Verification

- `uv run pytest`：**84 passed**
- `xcodebuild ... build` / `test`：**BUILD SUCCEEDED** / **TEST SUCCEEDED**
- 清理 `DerivedData/SonusCompanion-*` 与 `SonusCompanion/build`

### Next

- 真机回归：重新打包安装 Companion，切换 Kokoro ↔ Qwen3 多次，确认不再出现 `address already in use` 与 MPS 合成崩溃
- 可选：`scripts/simulate-qwen-engine-switch.sh` 在本机模型就绪下再跑一遍 3 阶段

### Notes

- 用户当前 `/Applications/Sonus.app` 为旧版（日志显示仍在用 `PUT /engines/active` 热切换路径）；本次源码修复需重新构建安装后才生效
- 若仍偶发 MPS 崩溃，可设 `SONUS_QWEN_DEVICE=cpu` 强制 CPU 推理（延迟上升但稳定）

---

## 2026-06-30（Qwen 引擎切换稳定性）

### Done

- **Companion 引擎切换**：embedded 模式不再走 `PUT /engines/active` 热切换，改为 **restart backend**（`SONUS_ENGINE` + 干净进程），避免 Kokoro ONNX 与 Qwen PyTorch/MPS 同进程共存导致崩溃
- **启动兜底**：若 UserDefaults 为 `qwen3-tts` 但 addon/模型未就绪，自动回退 Kokoro 并提示
- **Python 内存释放**：`Qwen3TTSEngine.unload()` 增加 `gc.collect()` + `torch.mps/cuda.empty_cache()`；MPS 加载失败时回退 CPU
- **`EngineManager` / Kokoro `unload`**：切换后触发 `gc.collect()`

### Changed Files

- `SonusCompanion/SonusCompanion/AppState.swift`
- `src/sonus/engines/qwen3_tts.py`、`src/sonus/engines/kokoro.py`、`src/sonus/engine_manager.py`
- `docs/DEVLOG.md`

### Next

- 发版验证 Companion 切换 Qwen3 ↔ Kokoro 不再 backend 秒退

### Verification

- `pytest`：**82 passed**（含 `tests/test_qwen_engine_stability.py` 5 项：unload 计数、往返切换、可选依赖拒绝、gc、MPS→CPU 回退）
- `scripts/simulate-qwen-engine-switch.sh`：热切换 + 进程重启 + 2 轮快速重启循环，全部 TTS WAV 通过（本机 Application Support 模型 + qwen-addon）
- `xcodebuild -scheme SonusCompanion build test`：通过

---

## 2026-06-30（Companion Release — Lite 包 + Qwen 按需下载）

### Done

- **Lite Release**：`bundle-python-runtime.sh` 恢复仅 Kokoro 依赖（去掉 `--extra qwen`），`Sonus-macos.zip` 回到 ~120MB
- **Qwen addon**：新增 `scripts/bundle-qwen-addon.sh` → `Sonus-qwen-addon.zip`（~224MB，111 个增量 site-packages）
- **Companion 按需安装**：`QwenAddonManager` 从 GitHub Release 下载 addon → `Application Support/Sonus/qwen-addon/`；`BackendManager` 注入 `PYTHONPATH`
- **Qwen 模型**：`QwenModelManager` 用 embedded Python + `huggingface_hub` 下载 Qwen3 快照
- **Settings**：引擎切换 /「Download Qwen3 Components…」触发 runtime + 模型下载
- **CI**：发版附带两个 asset；校验 lite zip 不含 `torch/`

### Changed Files

- `scripts/bundle-python-runtime.sh`、`scripts/bundle-qwen-addon.sh`（新建）
- `SonusCompanion/build_app.sh`、`.github/workflows/companion-release.yml`
- `SonusCompanion/`：`QwenAddonManager.swift`、`QwenModelManager.swift`、`AppState.swift`、`BackendManager.swift`、`SettingsView.swift`、`GitHubReleaseClient.swift`
- `src/sonus/engine_manager.py`、`docs/DECISIONS.md`

### Next

- 发版 tag 验证 lite + addon 端到端（切换 Qwen3-TTS + TTS）

---

## 2026-06-29（多引擎 — Qwen3-TTS 热切换）

### Done

- **`EngineManager`**：单引擎驻留、in-flight 排空（30s 超时 → 409）、unload/load
- **HTTP**：`GET /engines`、`PUT /engines/active`；`/health` 增加 `engine`
- **`engine_manifest.yaml`**：Kokoro 资产 URL + Qwen3 HF repo
- **`Qwen3TTSEngine`**：官方 `qwen-tts` + 0.6B CustomVoice；逻辑音色映射（`zh_female` → `serena` 等）
- **OpenAI**：`model` 校验 active 引擎（`tts-1` → kokoro）
- **Companion**：Settings 引擎 Picker、`SONUS_ENGINE` spawn、运行时 `PUT /engines/active`
- **脚本**：`scripts/download-qwen3-model.sh`；`bundle-python-runtime.sh` 加 `--extra qwen`
- **验证**：pytest 77 passed；本机 `kokoro` ↔ `qwen3-tts` 热切换 + `POST /tts` WAV 通过

### Changed Files

- `src/sonus/engine_manager.py`、`engine_manifest.yaml`、`engines/qwen3_tts.py`、`voice_registry.py`
- `src/sonus/app.py`、`factory.py`、`model_status.py`、`service.py`、`openai_compat.py`、`config.py`
- `SonusCompanion/`：`SonusClient`、`AppState`、`BackendManager`、`SettingsView`、`TTSRequest.swift`
- `scripts/download-qwen3-model.sh`、`pyproject.toml`（optional `qwen`）
- `docs/DECISIONS.md`、`ARCHITECTURE.md`、`ROADMAP.md`

### Next

- Qwen3 模型按需下载 UI（Companion 进度条，当前用脚本）
- embedded Release 验证 Qwen3 包体积与首包延迟

---

### Done

- **根因**：`EmbeddedBackendConfig.resolvePythonExecutable` 对 `bin/python3.12` 调用 `resolvingSymlinksInPath()` 后返回 **`python/bin/python3.12`**（bundled 解释器），而非 venv shim。直接执行 bundled 解释器时 Python 以 `python/` 为 `sys.prefix`，**不读 `pyvenv.cfg`、不激活 venv**，`site-packages` 解析到 `python/lib/python3.12/site-packages`（只有 pip），找不到 `sonus` → `ModuleNotFoundError` → smoke test `exit 1` → `Backend exited unexpectedly (code 1)`。
- **修复**：`resolvePythonExecutable` 返回 venv shim `bin/python3.12`（不 resolve symlink），只在校验时用 resolved 路径确认指向 bundle 内。执行 shim 让 Python 读 `pyvenv.cfg` 激活 venv，`sys.prefix = sonus-runtime/`，site-packages 落在 `lib/python3.12/site-packages`（含 sonus）。
- **诊断增强**：
  - `BackendManager.spawnBackend` 异步流式读取子进程 stdout/stderr 写入 app log（`backend stderr: ...`），进程秒退时不再丢失错误。
  - `terminationHandler` 在 `code != 0` 时附 `recentBackendOutput` 摘要到失败消息。
  - spawn 前清理 `PYTHONPATH`/`PYTHONHOME`/`PYTHONDONTWRITEBYTECODE`，避免宿主环境污染 embedded venv。
  - `runtimeLaunchError()` 同样清理环境，并设 `currentDirectoryURL = /`，使 smoke test 与 spawn 行为一致。
- **验证**：本地 release build + `verify-embedded-runtime` 全过；`/Applications/Sonus.app` 启动后 backend `Running`，`/health` `models_ready=true`，`POST /tts` 返回 WAV。

### Changed Files

- `SonusCompanion/SonusCompanion/EmbeddedBackendConfig.swift`、`BackendManager.swift`
- `SonusCompanion/CHANGELOG.md`、`docs/DEVLOG.md`、`docs/ROADMAP.md`

### Next

- 推 tag **v0.3.4** 发版；用户升级后 embedded backend 应直接可用。

---

## 2026-06-28（Companion — v0.3.3 hotfix: sonus 未打入 bundle）

### Done

- **根因**：v0.3.2 runtime 用 `uv sync` 复制开发 `.venv`，`sonus` 为 editable（`sonus.pth` → CI/本机 `src/`），App 内 `ModuleNotFoundError: No module named 'sonus'`
- **修复**：`bundle-python-runtime.sh` 独立 `.bundle-venv` + `uv sync --no-editable`；校验 `sonus.__file__` 在 bundle 内
- **验证**：新增 `scripts/verify-embedded-runtime.sh`（import + `/health`）；`build_app.sh` / CI 发版前必跑；本机 `/Applications/Sonus.app` E2E 通过

### Changed Files

- `scripts/bundle-python-runtime.sh`、`scripts/verify-embedded-runtime.sh`
- `SonusCompanion/build_app.sh`、`.github/workflows/companion-release.yml`
- `SonusCompanion/EmbeddedBackendConfig.swift`、`CHANGELOG.md`、`Info.plist`

---

## 2026-06-28（Companion — v0.3.2 hotfix: embedded runtime dyld / exit 6）

### Done

- **根因**：v0.3.1 CI 打包时 `uv python find` 选中了 **python.org framework** 解释器；二进制硬编码 `/Library/Frameworks/Python.framework/Versions/3.12/Python`，用户机器无该路径 → dyld abort（**exit code 6**）→ `Backend exited unexpectedly` / `did not become ready on port 8000`（与模型是否就绪无关）
- **修复**：`bundle-python-runtime.sh` 强制 `--managed-python`；拒绝 framework 链接；sandbox + CI 校验 zip 内 `python3.12` 不引用 `Python.framework`
- **Companion**：`EmbeddedBackendConfig.runtimeLaunchError()` 启动前 smoke test；`BackendManager` 失败时记录 stderr
- **验证**：本地 bundle + `uvicorn` health `models_ready=true`；Xcode build 通过

### Changed Files

- `scripts/bundle-python-runtime.sh`、`SonusCompanion/build_app.sh`
- `.github/workflows/companion-release.yml`
- `SonusCompanion/EmbeddedBackendConfig.swift`、`BackendManager.swift`
- `SonusCompanion/CHANGELOG.md`

### Next

- 打 tag **v0.3.2** 发版；用户升级后 embedded backend 应可直接用 Application Support 模型目录

---

## 2026-06-28（Companion — 应用更新下载进度）

### Done

- **`UpdateDownloader`**：改用流式下载，按字节回报进度（百分比 + MB）；解压阶段显示「Extracting update…」
- **`AppUpdateController`**：新增 `downloadProgress`；下载时弹出浮动进度窗口
- **Settings → Updates**：下载中显示 `ProgressView` 与状态文案

### Changed Files

- `SonusCompanion/UpdateDownloader.swift`、`AppUpdateController.swift`、`SettingsView.swift`
- `SonusCompanion/CHANGELOG.md`

---

## 2026-06-28（Companion — v0.3.1 hotfix: embedded runtime symlinks）

### Done

- **根因**：v0.3.0 打包时 venv 的 `python3` 指向 CI/本机绝对路径（如 `/Library/Frameworks/Python.framework/...`），用户机器上为断链 → `Embedded runtime not found`
- **修复**：`bundle-python-runtime.sh` 复制 uv CPython prefix 到 `sonus-runtime/python/`，venv shim 改为相对 symlink
- **模型下载**：按字节更新进度（显示 MB），避免大文件长时间停在 0%
- 发版 **v0.3.1**

---

### Done

- **`BackendManager`**：Release 下 spawn/kill embedded uvicorn；health 轮询；Quit 清理子进程
- **`ModelManager`**：Kokoro 模型检测（Application Support / `SONUS_MODELS_DIR` / 自定义路径）+ 按需下载
- **`EmbeddedBackendConfig`**：bundled runtime 路径；Debug 默认外连 / Release 默认 embedded
- **Settings**：Backend 状态 + 端口；Advanced 外连 URL / 自定义模型目录
- **Python**：`SONUS_MODELS_DIR`、`GET /health` 增加 `models_ready`；`model_status.py`
- **打包**：`scripts/bundle-python-runtime.sh`；`SonusCompanion/build_app.sh release` 嵌入 venv
- **测试**：pytest 71 passed；Xcode `ModelManagerTests` + 全量单元测试通过

### Changed Files

- `SonusCompanion/BackendManager.swift`、`ModelManager.swift`、`EmbeddedBackendConfig.swift`
- `AppState.swift`、`SettingsView.swift`、`MenuBarView.swift`
- `src/sonus/config.py`、`app.py`、`model_status.py`
- `scripts/bundle-python-runtime.sh`、`SonusCompanion/build_app.sh`
- `docs/COMPANION.md`、`ARCHITECTURE.md`、`ROADMAP.md`、`DECISIONS.md`（016）

### Next

- `./build_app.sh release` 端到端验证（含首次模型下载 + ⌥Esc）
- Phase 1.5：embedded bundle ffmpeg（MP3）

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
