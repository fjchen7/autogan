# autogan

[简体中文](./README.zh-CN.md)

> A file-based long-running agent harness for software work, built around a Generator / Evaluator loop.

> [!IMPORTANT]
> This project is an implementation of GAN workflow from Anthropic's article: [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps).

## Overview

`autogan` runs long coding tasks as a repeated workflow:

- a **Generator** proposes and implements the next step
- an **Evaluator** reviews it with a stricter standard
- an **Orchestrator** moves the process forward through files in `.gan/`

This helps with common long-running agent failure modes:

- drifting away from the original goal
- starting implementation before defining scope
- self-review that is too lenient
- losing context in long chat sessions

## What it solves

Use `autogan` for tasks that:

- run long enough that a single prompt is not enough
- need an agent to review code before the work moves on
- should run as automatically as possible with minimal human intervention

It is a good fit for long-running, automated coding workflows where implementation and review both need to happen inside the loop.

## Requirements

You need `jq` and `tmux` to run the workflow.

Supported agent types:

- `opencode`
- `claude`
- `codex`

> [!NOTE]
> The workflow expects to run inside a Git repository and uses Git to check cleanliness and record `.gan` state changes.

## Install

Install `autogan` by running:

```bash
# Install into the current directory:
./install.sh
# Install into specified directory:
./install.sh --dir /path/to/project
```

This creates:

```text
.gan/
autogan.sh
```

## Usage

1. Open a `tmux` session.
2. Configure your agents in `.gan/config.json`.
3. Make sure the git workspace is clean.
4. Start the workflow:

```bash
./autogan.sh "Build a collaborative note-taking app with comments, search, and version history."
```

Default `config.json`:

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
> Context window management is delegated to the agent CLI itself. In practice, this workflow relies on the CLI's built-in auto-compaction / summarization behavior to keep long-running sessions going.

> [!CAUTION]
> Remember to configure agent permissions in `config.json`. If missing, the agent may stop and wait for manual approval instead of continuing the workflow. For opencode, the configuration to skip permissions is
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
