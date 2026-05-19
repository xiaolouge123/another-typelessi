# 文本修正监听功能

## 功能概述

这个功能通过监听用户对语音识别输出的修改，自动学习和改进后续的文本润色（Polish）质量。

## 工作流程

1. **语音输入** → 用户按 Fn 键进行语音输入
2. **ASR 识别** → Deepgram 或 OpenRouter Whisper 转录音频
3. **文本润色** → GPT 根据历史修正记录优化文本
4. **输出粘贴** → 文本粘贴到光标位置
5. **监听修改** → 系统在接下来的 30 秒内监听文本变化（每 5 秒检查一次）
6. **相似度匹配** → 如果检测到的文本与输出相似度 ≥ 70%，记录为修正
7. **上下文学习** → 下次润色时，使用最近 20 条修正记录作为参考

## 核心参数

- **监听时长**: 30 秒
- **轮询间隔**: 5 秒（共监听 6 次）
- **相似度阈值**: 70%
- **多句拼接窗口**: 60 秒内的连续输入会尝试拼接匹配
- **上下文记录数**: 最近 20 条修正记录
- **最大存储**: 100 条修正记录

## 技术实现

### 新增文件

1. **CorrectionRecord.swift** - 修正记录数据模型和存储
2. **TextSimilarity.swift** - Levenshtein 距离相似度计算
3. **TextChangeMonitor.swift** - 文本变化监听器
4. **TextContextReader.swift** - 通过 Accessibility API 读取文本

### 修改文件

1. **AppDelegate.swift** - 集成监听器，在粘贴后启动监听
2. **OpenRouterClient.swift** - Polish prompt 中加入修正上下文
3. **PreferencesWindowController.swift** - 添加修正历史查看 UI
4. **SettingsViewModel.swift** - 添加修正记录管理

## 使用场景示例

### 场景 1: 技术术语纠正

用户说："cube control"
- ASR 输出: "cube control"
- 用户修改为: "kubectl"
- 系统记录: "cube control" → "kubectl"
- 下次用户说 "cube control" 时，Polish 会自动纠正为 "kubectl"

### 场景 2: 专有名词大小写

用户说："react native"
- ASR 输出: "react native"
- 用户修改为: "React Native"
- 系统记录: "react native" → "React Native"
- 下次会自动使用正确的大小写

### 场景 3: 多句连续输入

用户在 60 秒内连续进行 3 次语音输入：
- 第 1 句: "今天天气不错"
- 第 2 句: "我们去公园"
- 第 3 句: "散步吧"

用户将这三句合并修改为: "今天天气不错，我们去公园散步吧。"

系统会检测到拼接后的相似度，记录这个修正。

## UI 功能

在设置窗口中新增 "Correction History" 部分：

- 显示已记录的修正数量
- 列表展示每条修正记录：
  - 时间戳
  - 相似度百分比
  - ASR 输出（红色）
  - 用户修正（绿色）
- 刷新按钮：重新加载记录
- 清除按钮：清空所有修正历史

## 数据存储

修正记录存储在：
```
~/Library/Application Support/AnotherTypeless/corrections.json
```

格式：
```json
[
  {
    "id": "UUID",
    "timestamp": "2026-05-14T12:34:56Z",
    "asrOutput": "cube control",
    "userCorrected": "kubectl",
    "similarity": 0.75,
    "sessionID": 123
  }
]
```

## 日志记录

所有监听活动都会记录到 dictation.log：

```
[monitor] start sessionID=123 duration=30.0s interval=5.0s text=...
[monitor] poll=1 sessionID=123 read=150 chars
[monitor] matched sessionID=123 similarity=0.85
[correction] recorded sessionID=123 similarity=0.85 asr=... corrected=...
```

## 限制和注意事项

1. **Accessibility 权限**: 需要授予应用 Accessibility 权限才能读取文本
2. **应用兼容性**: 
   - ✅ 原生 macOS 应用（TextEdit, Notes, Mail）
   - ✅ 大部分文本编辑器（VSCode, Sublime, Xcode）
   - ⚠️ 浏览器输入框（支持有限）
   - ❌ 某些 Electron 应用和自定义渲染应用
3. **隐私**: 只在粘贴后的 30 秒内读取，不会持续监听
4. **性能**: 每 5 秒轮询一次，对系统影响极小

## 未来改进方向

1. 支持用户手动标记修正（不依赖自动检测）
2. 导出/导入修正记录
3. 按应用或文档类型分类修正记录
4. 更智能的相似度算法（考虑语义而非仅字符）
5. 支持正则表达式规则（如自动替换特定模式）
