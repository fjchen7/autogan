本文档描述 gan 工作流的文件结构。

## 目录

工作流的沟通和记录都保存在 `.gan/` 目录中：

```
.gan/
  config.json    # 系统配置。
  state.json     # 当前流程状态。
  summary.json   # 每轮工作的全局精简历史摘要。
  history.json   # 启动orchestrator时的用户原始需求和覆盖的轮数记录。

  current/       # 当前轮的工作文件夹，包含合同和反馈的往返记录。当每一轮结束后，这个文件夹会被归档到 `rounds/` 里。
    contract.md  # 当前轮的合同。
    review.md    # 当前轮反馈的往返记录，在这里查看evaluator的反馈，进行修改后并留下你的回应。

  rounds/        # 历史轮次的归档文件夹。
    001/
      contract.md
      review.md
    002/
      ...
```

## `state.json`

典型结构：

```json
{
  "round": 1,
  "status": "ROUND_STARTED",
  "updatedAt": "2026-04-06T10:00:00Z"
}
```

## `summary.json`

典型结构：

```json
[
  {
    "round": 1,
    "goal": "搭建 Electron + Bun sidecar 骨架",
    "result": "PASS",
    "closeReason": "骨架跑通，可进入主问答链路",
    "repairCount": 1,
    "note": "使用了 Bun 来替代 Node，解决了性能和兼容性问题；实现了主窗口和侧边栏的基本通信机制；搭建了初步的日志系统；但在某些边界情况下仍有内存泄漏，需要在下一轮继续修复",
    "startedAt": "2026-04-06T10:00:00Z",
    "endedAt": "2026-04-06T10:48:00Z"
  }
]
```

## `history.json`

典型结构：

```json
[
  {
    "prompt": "...", // 用户原始需求
    "rounds": [1, 2], // 这段需求实际覆盖了哪些轮次
    "startedAt": "...", // 开始时间
    "updatedAt": "..." // 最后更新时间
  }
]
```

## `contract.md`

格式：

```md
# Round <N> Contract

## Goal

<!-- 这一轮的目标是什么？请清楚、具体地描述。 -->

## Expectation

<!-- 这一轮完成后，大致应该达到什么方向和效果。具体如何验收，由 evaluator 决定。 -->

## Notes

<!-- 额外说明 -->
```

## `review.md`

```md
# Round <N> Review

## Contract Negotiation

<!-- 这一轮的合同协商记录。每次修改合同后，在这里留下记录，说明修改了什么，为什么修改。 -->

### Generator

- Updated:
- Note:

### Evaluator

- Verdict: REVISE / ACCEPTED
- Review Comment:

<!-- Verdict 允许的值：
- `REVISE`: evaluator认为合同需要修改。
- `ACCEPTED`: evaluator认为合同可以接受 -->

## Cycle 1

<!-- 这一轮的第一次实现或修复记录。每次实现或修复后，在这里留下记录，说明改了什么，为什么改。 -->

### Generator

- Updated:
- Note:

### Evaluator

- Verdict: PASS / FAIL
- Review Comment:

<!-- Verdict 允许的值：
- `PASS`: 这一轮目标达成。你等待orchestrator决定是否进入下一轮。
- `FAIL`: 这一轮还有问题，需要继续修复。-->
```