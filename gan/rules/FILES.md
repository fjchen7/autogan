This document describes the file structure of the GAN workflow.

## Directory

Workflow communication and records are stored in the `.gan/` directory:

```
.gan/
  config.json    # System configuration.
  state.json     # Current workflow state.
  summary.json   # A compact global history summary for each round of work.
  history.json   # The original user requests recorded when the orchestrator starts, plus the rounds they cover.

  current/       # The working folder for the current round, including the back-and-forth records for the contract and feedback. After each round ends, this folder is archived into `rounds/`.
    contract.md  # The contract for the current round.
    review.md    # The back-and-forth feedback record for the current round. Read the Evaluator's feedback here, revise the work, and leave your response.

  rounds/        # Archive folder for past rounds.
    001/
      contract.md
      review.md
    002/
      ...
```

## `state.json`

Typical structure:

```json
{
  "round": 1,
  "status": "ROUND_STARTED",
  "updatedAt": "2026-04-06T10:00:00Z"
}
```

## `summary.json`

Typical structure:

```json
[
  {
    "round": 1,
    "goal": "Build the Electron + Bun sidecar scaffold",
    "result": "PASS",
    "closeReason": "The scaffold works and the main Q&A flow can begin",
    "repairCount": 1,
    "note": "Bun replaced Node to address performance and compatibility issues; the basic communication path between the main window and sidebar was implemented; however, some edge cases still leak memory and need another round of fixes",
    "startedAt": "2026-04-06T10:00:00Z",
    "endedAt": "2026-04-06T10:48:00Z"
  }
]
```

## `history.json`

Typical structure:

```json
[
  {
    "prompt": "...", // Original user request
    "rounds": [1, 2], // Which rounds this request actually covers
    "startedAt": "...", // Start time
    "updatedAt": "..." // Last update time
  }
]
```

## `contract.md`

Format:

```md
# Round <N> Contract

## Goal
<!-- What is the goal of this round? Describe it clearly and specifically. -->

## Expectation
<!-- After this round is complete, what direction and result should roughly be achieved? The Evaluator decides the exact acceptance criteria. -->

## Notes
<!-- Additional notes -->
```

## `review.md`

```md
# Round <N> Review

## Contract Negotiation
<!-- The contract negotiation record for this round. After each contract revision, leave a note here explaining what changed and why. -->

### Generator

- Updated:
- Note:

### Evaluator

- Verdict: REVISE / ACCEPTED
- Review Comment:
<!-- Allowed values for Verdict:
- `REVISE`: the Evaluator thinks the contract needs revision.
- `ACCEPTED`: the Evaluator thinks the contract is acceptable. -->

## Cycle 1
<!-- The first implementation or fix record for this round. After each implementation or fix, leave a note here explaining what changed and why. -->

### Generator
- Updated:
- Note:

### Evaluator
- Verdict: PASS / FAIL
- Review Comment:
<!-- Allowed values for Verdict:
- `PASS`: the goal of this round is met. Wait for the orchestrator to decide whether to enter the next round.
- `FAIL`: this round still has problems and needs more fixes. -->
```
