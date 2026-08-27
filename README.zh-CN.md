[English](README.md)

# Liang

> 让 AI IDE 的工作状态，在 macOS 屏幕上「看得见」。

Liang 是一个 macOS 菜单栏常驻应用。它通过刘海周围一圈柔和的光晕、跟随鼠标的光晕小球，以及菜单栏图标，实时提示 AI IDE（Coding Agent）的工作状态——空闲、处理中、等待确认、成功、出错。你无需切换窗口，一眼就能知道 Agent 现在是在思考、在等你确认，还是已经完成。

## 功能特性

- **刘海光晕**：自动识别刘海屏，在刘海周围渲染一圈非侵入式的状态光晕；无刘海设备降级为屏幕顶部中央光晕。
- **光标光晕**：跟随鼠标的小光晕，同样随状态变色。
- **菜单栏状态色**：菜单栏图标小球随状态呼吸/脉冲，深色/浅色模式自适应。
- **多状态区分**：`idle` / `processing` / `waiting` / `success` / `error` / `unknown` / `disconnected`，颜色与动画均可自定义。
- **低干扰**：尊重 macOS「减少动态效果」与「低电量模式」，自动降级为静态光晕，省电且符合系统辅助功能规范。

## 安装

1. 从 [Releases](https://github.com/fangshili/Liang/releases) 下载最新版 `Liang-x.y.z.dmg`。
2. 打开 DMG，将 `Liang.app` 拖入「应用程序」。

要求：macOS 14.0+，Apple Silicon（arm64）。

## 使用方法

1. 启动 Liang 后，菜单栏会出现一个状态小球图标。
2. 首次启动会进入引导流程，引导你为 Cursor、Claude Code、Codex、CodeBuddy 一键配置 Hooks 桥接；也可随时在「设置」中管理各 IDE 的接入状态。
3. 配置完成后，当对应 IDE 中的 Agent 开始工作、等待你确认、或结束任务时，刘海光晕与菜单栏图标会随之变色。
4. 点击菜单栏图标可查看当前状态、来源与最近一次事件；在「设置」中可自定义各状态的颜色、光晕开关、亮度、模糊、动画速度等。

## 隐私保护

Liang 以「本地优先、最小收集」为原则，**不读取、不上传你的代码、Prompt、文件内容**。

- **只处理状态元数据**：桥接脚本仅从 Hooks 事件中提取状态所需的少量元数据字段（来源、事件类型、时间戳、会话/任务标识、工具名、状态等），**从不提取** Prompt 正文、代码内容或文件内容。
- **数据仅存本地**：事件写入本机 `~/.liang/` 目录，事件文件大小上限 10 MB（超出自动截断），日志只记录异常信息、不含事件原文。
- **无遥测、无云端同步**：Liang 不采集任何使用数据，不需要账号，不向任何服务器上传你的内容。
- **唯一网络请求**：自动更新检查（Sparkle）会访问公开的更新源 `appcast.xml`，用于检测新版本，不携带任何用户数据。
- **配置本地持久化**：所有设置保存在本机 `UserDefaults`，损坏时自动回退到安全默认值。

---

## 支持的 Coding Agent 及限制

Liang 通过各 IDE 的官方 Hooks 机制感知状态，不注入、不改动你的代码。目前支持 4 个 Coding Agent：

| Agent | Hooks 位置 | 等待确认（waiting） | 成功/失败区分 |
|---|---|---|---|
| **Cursor** | `~/.cursor/hooks.json` | ✅ | ✅ |
| **Claude Code** | `~/.claude/settings.json` | ✅ | ✅ |
| **Codex** | `~/.codex/hooks.json` | ✅ | ❌ 恒 success |
| **CodeBuddy** | `~/.codebuddy/settings.json` | ⚠️ 仅 CLI | ❌ 恒 success |

### 已知限制

**客户端生效范围**
- **Codex**：Hook 需在 CLI 中运行 `/hooks` 信任后才生效，桌面版无法信任。
- **CodeBuddy**：桌面版仅支持 7 种 Hooks 事件，`waiting`（权限确认 / 深度思考）仅在 CLI 版可感知。

**成功 / 失败区分**
- **Codex、CodeBuddy**：任务结束事件（`Stop`）不含成功/失败状态字段，因此统一显示为「成功」。

**事件触发时机**
- **Codex**：`SessionEnd` 事件在会话空闲约 30 分钟后才触发。

**版本要求**
- **Claude Code**：`prompt_id` 字段需 Claude Code ≥ v2.1.196。

> ⚠️ **Claude Code 与 Codex 尚未经过作者验证**，实际表现可能与预期有偏差，使用中如有异常欢迎反馈。
>
> 以上限制均源于各 IDE Hooks 规范本身，非 Liang 缺陷。

---

如果有问题和建议，可以[提 issue](https://github.com/fangshili/Liang/issues) 或[向作者反馈](mailto:fangshi.li.cn@gmail.com)。
