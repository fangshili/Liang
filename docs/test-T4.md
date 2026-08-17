# 测试脚本 · T4｜Cursor Hooks Adapter

运行方式：在 Xcode 中打开本文件夹的 `Package.swift` 点 Run，或终端执行 `swift run`。

## 前提

1. 已存在 `~/.liang/cursor-events.jsonl`（不存在时 Adapter 会自动创建空文件）。
2. 尚未配置 Cursor Hook，本测试通过手动写入事件文件验证 Adapter。

## 步骤

1. 运行 App，确认刘海/顶部光晕正常显示。
2. 打开终端，执行：
   ```bash
   echo '{"source":"cursor","hook":"sessionStart","timestamp":"2026-07-27T12:00:00.000000Z","conversation_id":"test-1"}' >> ~/.liang/cursor-events.jsonl
   ```
3. 观察菜单栏图标或光晕是否有反应（T4 仅验证事件被正确接收，具体状态映射在 T5）。
4. 继续写入多条事件：
   ```bash
   echo '{"source":"cursor","hook":"beforeSubmitPrompt","timestamp":"2026-07-27T12:00:01.000000Z","conversation_id":"test-1"}' >> ~/.liang/cursor-events.jsonl
   echo '{"source":"cursor","hook":"afterAgentResponse","timestamp":"2026-07-27T12:00:05.000000Z","conversation_id":"test-1"}' >> ~/.liang/cursor-events.jsonl
   echo '{"source":"cursor","hook":"stop","timestamp":"2026-07-27T12:00:06.000000Z","conversation_id":"test-1","status":"completed"}' >> ~/.liang/cursor-events.jsonl
   ```
5. 点击菜单栏图标，查看是否有最近事件信息（如果 T4 已接入菜单栏调试入口）。
6. 删除 `~/.liang/cursor-events.jsonl` 文件，确认 Adapter 进入未连接/未知状态而不是崩溃。
7. 重新创建空文件，确认监听自动恢复。

## 预期

- Adapter 能实时读取追加到 `cursor-events.jsonl` 的新事件。
- 无效 JSON 行被跳过，不中断后续事件处理。
- 文件被删除或不可读时，Adapter 报告错误且不崩溃。
- 不读取、不修改 Cursor 自身的文件或配置。

## 性能

- 事件追加后 100ms 内应被 App 感知。
- 空闲时无显著 CPU 占用。

## 判定

Adapter 正确解析事件、错误处理稳健 = 通过。

## 不通过怎么反馈

描述写入的事件内容、看到的现象，并附 `~/.liang/cursor-events.jsonl` 样本。
