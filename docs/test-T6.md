# 测试脚本 · T6｜状态到光晕的映射

运行方式：在 Xcode 中打开本文件夹的 `Package.swift` 点 Run，或终端执行 `swift run`。

## 前提

- T4、T5 已完成，Cursor Hook 事件链路已跑通。
- `~/.liang/cursor-events.jsonl` 存在且 Liang 正在监听。

## 测试内容

### 1. 颜色映射

通过向事件文件写入不同事件，观察刘海光晕颜色变化：

```bash
# idle：默认橙色 #E58325（无事件或 sessionEnd）
echo '{"source":"cursor","hook":"sessionEnd","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1"}' >> ~/.liang/cursor-events.jsonl

# processing：蓝色 #00BFFF
echo '{"source":"cursor","hook":"beforeSubmitPrompt","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1"}' >> ~/.liang/cursor-events.jsonl

# waiting：金色 #FFD700
echo '{"source":"cursor","hook":"afterAgentResponse","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1"}' >> ~/.liang/cursor-events.jsonl

# success：绿色 #00FF52
echo '{"source":"cursor","hook":"stop","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1","status":"completed"}' >> ~/.liang/cursor-events.jsonl

# error：红色 #FF3B30
echo '{"source":"cursor","hook":"postToolUseFailure","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1","failure_type":"timeout"}' >> ~/.liang/cursor-events.jsonl
```

### 2. 动画模式

- **idle**：呼吸动画（使用用户设置的呼吸速度）。
- **processing**：中速呼吸。
- **waiting**：慢速脉冲（3 秒周期，明暗变化更明显）。
- **success**：快速脉冲（0.6 秒周期），最多保持 3 分钟或直到新事件。
- **error**：急促闪烁（0.3 秒周期），必须非常明显。
- **unknown/disconnected**：静态光晕，无动画。

### 3. 状态优先级

1. 先触发 error：
   ```bash
   echo '{"source":"cursor","hook":"postToolUseFailure","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1","failure_type":"timeout"}' >> ~/.liang/cursor-events.jsonl
   ```
2. 再触发 processing：
   ```bash
   echo '{"source":"cursor","hook":"beforeSubmitPrompt","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1"}' >> ~/.liang/cursor-events.jsonl
   ```
3. 观察：error 状态的红色光晕应保持不变，不应被 processing 覆盖为蓝色。
4. 点击菜单栏“清除错误状态”，确认光晕恢复为 idle 橙色。

### 4. waiting 不超时

1. 触发 waiting：
   ```bash
   echo '{"source":"cursor","hook":"afterAgentResponse","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1"}' >> ~/.liang/cursor-events.jsonl
   ```
2. 等待 60 秒以上，确认光晕仍保持金色 waiting 状态。
3. 发送新的 beforeSubmitPrompt，确认光晕变为蓝色 processing。

### 5. success 保持时间

1. 触发 success：
   ```bash
   echo '{"source":"cursor","hook":"stop","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)'","conversation_id":"test-1","status":"completed"}' >> ~/.liang/cursor-events.jsonl
   ```
2. 确认绿色 success 光晕保持，最多 3 分钟后自动恢复 idle 橙色。
3. 在 success 期间发送 processing 事件，确认光晕立即变为蓝色。

### 6. 减少动态效果 / 低电量模式

1. 系统设置 → 辅助功能 → 显示 → 开启“减少动态效果”。
2. 触发 processing/waiting/success/error，确认光晕仍有颜色，但动画停止（变为静态）。
3. 关闭“减少动态效果”，确认动画恢复。

## 预期

- 每种状态都有明显不同的颜色。
- error 和 waiting 必须能被用户明显识别（红色急促闪烁、金色慢速脉冲）。
- error 不被 processing 覆盖。
- waiting 不超时。
- success 最多保持 3 分钟或被新事件打断。
- reduceMotion/lowPower 下动画停止但颜色保留。

## 不通过怎么反馈

描述触发的事件、看到的光晕颜色和动画、期望的行为，并附 `~/.liang/cursor-events.jsonl` 最近 10 行。
