# autogan

[English](./README.md)

> 一个基于文件的 agent harness，可长时间运行。围绕 Generator / Evaluator 循环构建。

> [!IMPORTANT]
> 这个项目是对 Anthropic 文章 [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps) 所提到的 GAN 工作流的实现。

## 概览

`autogan` 会把长任务拆成重复执行的工作流：

- **Generator** 提出并实现下一步工作
- **Evaluator** 用更严格的标准进行评审
- **Orchestrator** 通过 `.gan/` 中的文件推动流程前进

它主要解决长时运行 agent 常见的几个问题：

- 逐渐偏离原始目标
- 还没定义范围就开始实现
- 自我评审过于宽松
- 会话一长就丢失上下文

## 能解决什么问题

`autogan` 适合这类任务：

- 单次 prompt 不足以完成，需要长时间运行
- 需要 agent 在继续推进前审查代码
- 希望流程尽可能自动运行，尽量少人工介入

它尤其适合实现和评审都要放进同一个循环里的长时自动化编码工作流。

## 依赖

运行这个工作流需要 `jq` 和 `tmux`。

支持的 agent 类型：

- `opencode`
- `claude`
- `codex`

> [!NOTE]
> 这个工作流默认运行在 Git 仓库中，并会使用 Git 检查工作区是否干净，以及记录 `.gan` 状态变化。

## 安装

运行下面的命令安装 `autogan`：

```bash
# 安装到当前目录：
./install.sh
# 安装到指定目录：
./install.sh --dir /path/to/project
```

安装后会创建：

```text
.gan/
autogan.sh
```

## 使用

1. 先打开一个 `tmux` 会话。
2. 在 `.gan/config.json` 里配置你的 agents。
3. 确保当前 Git 工作区是干净的。
4. 启动工作流：

```bash
./autogan.sh "Build a collaborative note-taking app with comments, search, and version history."
```

默认的 `config.json` 例如：

```json
{
  "maxRounds": 10,
  "maxRepairCount": 3,
  "confirmDiscardOnRestart": true,
  "generator": {
    "command": "codex --ask-for-approval never",
    "type": "codex"
  },
  "evaluator": {
    "command": "claude --dangerously-skip-permissions",
    "type": "claude"
  }
}
```

> [!NOTE]
> 上下文窗口管理不是这个脚本自己做的，而是交给 agent CLI 处理。实际运行时，这个工作流依赖 agent CLI 自带的自动压缩 / 自动总结机制来维持长会话。

> [!CAUTION]
> 记得在 `config.json` 里配置 agent 权限。不配的话，agent 可能会停下来等待人工批准，而不是继续自动执行。对于 opencode，跳过权限确认的配置例如：
>
> ```json
> {
> ...
>   "generator": {
>    "command": "opencode",
>    "env": {
>      "OPENCODE_PERMISSION": {
>        "*": "allow"
>      }
>    },
>    "type": "opencode"
>   },
> ...
> ```
