# 测试脚本 · T5｜状态引擎和状态详情

运行方式：在 Xcode 中打开本文件夹的 `Package.swift` 点 Run，或终端执行 `swift run`。

## 前提

- T4 已完成，`~/.liang/cursor-events.jsonl` 存在且 Liang 正在监听。
- 测试通过手动写入事件文件模拟 Cursor Hook。

## 步骤

1. 运行 App，点击菜单栏 Liang 图标。
2. 确认菜单显示：
   - 状态：未连接（如果事件文件为空）
   - 最近事件：无
3. 在终端写入 processing 事件：
   ```bash
   echo '{"source":"cursor","hook":"beforeSubmitPrompt","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1","generation_id":"gen-1"}' >> ~/.liang/cursor-events.jsonl
   ```
4. 再次打开菜单，确认状态变为"处理中"，最近事件显示 `beforeSubmitPrompt` 和相对时间。
5. 连续写入相同事件 3 次，确认菜单状态没有反复跳动（去重生效）。
6. 写入 afterAgentResponse 事件：
   ```bash
   echo '{"source":"cursor","hook":"afterAgentResponse","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1"}' >> ~/.liang/cursor-events.jsonl
   ```
7. 确认状态变为"等待确认"。
8. 写入 stop completed 事件：
   ```bash
   echo '{"source":"cursor","hook":"stop","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1","status":"completed"}' >> ~/.liang/cursor-events.jsonl
   ```
9. 确认状态变为"成功"，约 3 秒后自动恢复为"空闲"。
10. 写入 postToolUseFailure 事件：
    ```bash
    echo '{"source":"cursor","hook":"postToolUseFailure","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1","failure_type":"timeout"}' >> ~/.liang/cursor-events.jsonl
    ```
11. 确认状态变为"错误"，并且菜单出现"清除错误状态"选项。
12. 点击"清除错误状态"，确认状态恢复为"空闲"。
13. 写入 processing 事件后不继续写入，等待 60 秒，确认状态超时恢复为"空闲"。
14. 删除 `~/.liang/cursor-events.jsonl`，确认状态变为"未连接"或"未知"，App 不崩溃。

### 启动时不应回放历史事件

1. 先停止 Liang。
2. 写入一条 5 分钟前的 processing 事件：
   ```bash
   OLD_TIME=$(date -u -v-5M +%Y-%m-%dT%H:%M:%S.000000Z)
   echo '{"source":"cursor","hook":"beforeSubmitPrompt","timestamp":"'"$OLD_TIME"'","conversation_id":"old"}' > ~/.liang/cursor-events.jsonl
   ```
3. 重新启动 Liang，打开菜单。
4. 期望：状态不应变为"处理中"；应显示"未连接"或"未知"（因为没有新事件）。
5. 再写入一条当前时间的 processing 事件，确认状态正确变为"处理中"。

## 第二阶段：真实 Cursor 验证（已验证）

1. 部署 Hook：
   ```bash
   cd /Users/fangshili/CodeBuddy/liang
   ./hooks/install.sh
   ```
2. **完全退出并重新启动 Cursor**（Cmd+Q，不能只关窗口）。
3. 启动 Liang App。
4. 在一个终端持续观察事件文件：
   ```bash
   tail -f ~/.liang/cursor-events.jsonl
   ```
5. 在 Cursor 中发起一次普通对话，确认事件文件出现 `beforeSubmitPrompt`、`afterAgentThought`、`afterAgentResponse`、`stop` 等事件。
6. 观察 Liang 菜单状态是否跟随变化：
   - 发送消息后应显示"处理中"
   - AI 回复后应显示"等待确认"
   - 任务完成后应短暂显示"成功"再回"空闲"
7. 触发一次错误场景（例如让 Cursor 调用一个失败的工具或取消操作），确认状态变为"错误"，菜单出现"清除错误状态"。

### 如果事件文件没有写入任何内容

1. 检查 `~/.cursor/hooks.json` 中 `command` 是否为**绝对路径**。
2. 检查 `~/.cursor/hooks/liang-bridge.sh` 是否存在且可执行。
3. 检查 `~/.liang/bridge-error.log` 是否有 `stdin is empty` 报错；如果有，说明桥接脚本没有正确输出 JSON 响应，请重新运行 `./hooks/install.sh`。
4. 检查 Cursor 是否已**完全重启**。

## 预期

- 每个有效事件都能在菜单中看到对应的状态变化。
- 重复事件在 1 秒内不重复触发状态变化。
- 成功状态保持 3 秒后自动恢复。
- 错误状态保持到下一次事件或用户手动清除。
- processing/waiting 状态 60 秒无新事件自动恢复为 idle。
- 文件丢失时 Adapter 报告未连接，App 不崩溃。
- 真实 Cursor 操作后，`~/.liang/cursor-events.jsonl` 有事件写入，Liang 状态正确映射。

## 性能

- 事件追加后 100ms 内菜单状态更新。
- 空闲时无显著 CPU 占用。

## 判定

状态映射正确、去重生效、超时和错误恢复稳健、真实 Cursor 事件链路通 = 通过。

## 不通过怎么反馈

描述操作步骤、Cursor 版本、看到的菜单状态变化，并附 `~/.liang/cursor-events.jsonl` 内容和 `~/.cursor/hooks.json` 内容。
