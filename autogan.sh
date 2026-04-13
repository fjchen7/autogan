#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAN_DIR="$ROOT_DIR/.gan"
CURRENT_DIR="$GAN_DIR/current"
ROUNDS_DIR="$GAN_DIR/rounds"
CONFIG_FILE="$GAN_DIR/config.json"
STATE_FILE="$GAN_DIR/state.json"
HISTORY_FILE="$GAN_DIR/history.json"
WORKFLOW_RULE_FILE="$GAN_DIR/rules/WORKFLOW.md"
FILES_RULE_FILE="$GAN_DIR/rules/FILES.md"
GENERATOR_RULE_FILE="$GAN_DIR/rules/GENERATOR.md"
EVALUATOR_RULE_FILE="$GAN_DIR/rules/EVALUATOR.md"
LOOP_SECONDS=30
DIRTY_LIMIT=20
PANE_READY_SLEEP=8

GENERATOR_PROMPT_PREFIX='You are the Generator, currently working inside the GAN workflow. After you finish your work, you must **git commit the deliverables for this round and make sure git status is clean** before handing off.'
EVALUATOR_PROMPT_PREFIX='You are the Evaluator, currently working inside the GAN workflow. After you finish your work, you must **git commit the deliverables for this round and make sure git status is clean** before handing off.'

declare -A PROMPTS=()

PROMPTS[generator_round_start]="${GENERATOR_PROMPT_PREFIX}"$'\n\nOriginal user request:\n```\n%s\n```\n\nAdvance this round of work around the user'\''s original request.\n\nThis is Round %s. Read the files in `.gan/state.json`, `.gan/summary.json`, and `.gan/current/`, then begin the contract phase for this round.'

PROMPTS[generator_contract_revision]="${GENERATOR_PROMPT_PREFIX}"$'\n\nThe contract for Round %s needs revision. Read `.gan/state.json`, `.gan/summary.json`, and the files in `.gan/current/`, then respond and hand off.'

PROMPTS[generator_implementation]="${GENERATOR_PROMPT_PREFIX}"$'\n\nOriginal user request:\n```\n%s\n```\n\nThe contract for Round %s has been approved. Read the original user request, `.gan/state.json`, `.gan/summary.json`, and the files in `.gan/current/`, then start implementing this round'\''s goal.'

PROMPTS[generator_implement_revision]="${GENERATOR_PROMPT_PREFIX}"$'\n\nThe implementation for Round %s needs fixes. Read `.gan/state.json`, `.gan/summary.json`, and the files in `.gan/current/`, then fix the issues and hand off.'

PROMPTS[evaluator_contract]="${EVALUATOR_PROMPT_PREFIX}"$'\n\nOriginal user request:\n```\n%s\n```\n\nReview the Round %s contract with **critical thinking and the strictest standards**. Read `.gan/state.json`, `.gan/summary.json`, and the files in `.gan/current/`, then review, leave feedback, and hand off.'

PROMPTS[evaluator_implementation]="${EVALUATOR_PROMPT_PREFIX}"$'\n\nOriginal user request:\n```\n%s\n```\n\nReview the implementation for Round %s with **critical thinking and the strictest standards**. Review both the UI and the functional implementation. Do not stop at reading code; evaluate it by imitating real user behavior. Read `.gan/state.json`, `.gan/summary.json`, and the files in `.gan/current/`, then review, leave feedback, and hand off.'

show_help() {
  cat <<'EOF'
Run the autogan workflow orchestrator in the current project.

Usage:
  autogan.sh "<user_requirement>"
  autogan.sh [-h | --help]

Options:
  -h, --help              Show this help message.
EOF
}

debug_log() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M')"
  printf '[debug][%s] %s\n' "$ts" "$*" >&2
}

if ! command -v jq >/dev/null 2>&1; then
  printf 'Missing required command: jq\n' >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  printf 'Missing required command: tmux\n' >&2
  exit 1
fi

if [ $# -ge 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
  show_help
  exit 0
fi

ensure_gan_layout() {
  if [ ! -d "$GAN_DIR" ]; then
    printf 'Missing .gan directory: %s\n' "$GAN_DIR" >&2
    printf 'Run ./install.sh first.\n' >&2
    exit 1
  fi
}

if [ $# -lt 1 ]; then
  printf 'Missing user requirement. See %s --help\n' "$0" >&2
  exit 1
fi

USER_PROMPT="$1"

iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

build_env_assignments() {
  local env_json="$1"

  jq -rn --argjson env "$env_json" '
    $env
    | to_entries
    | map("\(.key)=\(.value | tojson | @sh)")
    | join(" ")
  '
}

build_system_prompt() {
  local role="$1"
  local role_rule_file=""

  case "$role" in
    generator)
      role_rule_file="$GENERATOR_RULE_FILE"
      ;;
    evaluator)
      role_rule_file="$EVALUATOR_RULE_FILE"
      ;;
    *)
      printf 'Unknown role for system prompt: %s\n' "$role" >&2
      exit 1
      ;;
  esac

  if [ ! -f "$WORKFLOW_RULE_FILE" ] || [ ! -f "$FILES_RULE_FILE" ] || [ ! -f "$role_rule_file" ]; then
    printf 'Missing system prompt rule files for role %s\n' "$role" >&2
    exit 1
  fi

  cat "$WORKFLOW_RULE_FILE"
  printf '\n\n'
  cat "$FILES_RULE_FILE"
  printf '\n\n'
  cat "$role_rule_file"
}

build_system_prompt_export_command() {
  local role="$1"

  case "$role" in
    generator)
      printf '%s\n' "export GAN_SYSTEM_PROMPT=\"\$({ cat .gan/rules/WORKFLOW.md; printf '\\n\\n'; cat .gan/rules/FILES.md; printf '\\n\\n'; cat .gan/rules/GENERATOR.md; })\""
      ;;
    evaluator)
      printf '%s\n' "export GAN_SYSTEM_PROMPT=\"\$({ cat .gan/rules/WORKFLOW.md; printf '\\n\\n'; cat .gan/rules/FILES.md; printf '\\n\\n'; cat .gan/rules/EVALUATOR.md; })\""
      ;;
    *)
      printf 'Unknown role for system prompt export: %s\n' "$role" >&2
      exit 1
      ;;
  esac
}

build_opencode_config_export_command() {
  local role="$1"
  local config_content=""

  case "$role" in
    generator)
      config_content='{"instructions":[".gan/rules/WORKFLOW.md",".gan/rules/FILES.md",".gan/rules/GENERATOR.md"]}'
      ;;
    evaluator)
      config_content='{"instructions":[".gan/rules/WORKFLOW.md",".gan/rules/FILES.md",".gan/rules/EVALUATOR.md"]}'
      ;;
    *)
      printf 'Unknown role for opencode config export: %s\n' "$role" >&2
      exit 1
      ;;
  esac

  printf "export OPENCODE_CONFIG_CONTENT='%s'\n" "$config_content"
}

build_agent_startup_commands() {
  local role="$1"
  local type="$2"
  local env_json="$3"
  local commands=()
  local env_assignments

  env_assignments="$(build_env_assignments "$env_json")"

  if [ -n "$env_assignments" ]; then
    commands+=("export $env_assignments")
  fi

  case "$type" in
    codex|claude)
      commands+=("$(build_system_prompt_export_command "$role")")
      ;;
    opencode)
      commands+=("$(build_opencode_config_export_command "$role")")
      ;;
    *)
      printf 'Unsupported agent type for startup commands: %s\n' "$type" >&2
      exit 1
      ;;
  esac

  if [ ${#commands[@]} -eq 0 ]; then
    printf '%s\n' 'true'
  else
    printf '%s\n' "${commands[@]}"
  fi
}

build_agent_shell_bootstrap() {
  local startup_commands="$1"
  local bootstrap_script=""
  local line

  while IFS= read -r line; do
    if [ -n "$line" ]; then
      bootstrap_script+="$line; "
    fi
  done <<EOF
$startup_commands
EOF

  printf '%s exec "$SHELL" -i' "$bootstrap_script"
}

build_agent_launch_command() {
  local type="$1"
  local command="$2"

  case "$type" in
    codex)
      printf '%s -c %q\n' "$command" 'developer_instructions="$GAN_SYSTEM_PROMPT"'
      ;;
    claude)
      printf '%s --append-system-prompt "$GAN_SYSTEM_PROMPT"\n' "$command"
      ;;
    opencode)
      printf '%s\n' "$command"
      ;;
    *)
      printf 'Unsupported agent type for launch command: %s\n' "$type" >&2
      exit 1
      ;;
  esac
}

read_config() {
  local allowed_agent_types='["opencode", "claude", "codex"]'
  local generator_env_json
  local evaluator_env_json

  MAX_ROUNDS="$(jq -r '.maxRounds // 10' "$CONFIG_FILE")"
  MAX_REPAIR_COUNT="$(jq -r '.maxRepairCount // 3' "$CONFIG_FILE")"
  CONFIRM_DISCARD="$(jq -r '.confirmDiscardOnRestart // true' "$CONFIG_FILE")"
  GENERATOR_COMMAND="$(jq -r '.generator.command // empty' "$CONFIG_FILE")"
  GENERATOR_TYPE="$(jq -r '.generator.type // empty' "$CONFIG_FILE")"
  EVALUATOR_COMMAND="$(jq -r '.evaluator.command // empty' "$CONFIG_FILE")"
  EVALUATOR_TYPE="$(jq -r '.evaluator.type // empty' "$CONFIG_FILE")"
  generator_env_json="$(jq -c '.generator.env // {}' "$CONFIG_FILE")"
  evaluator_env_json="$(jq -c '.evaluator.env // {}' "$CONFIG_FILE")"

  if [ -z "$GENERATOR_COMMAND" ]; then
    printf 'Missing required config: generator.command\n' >&2
    exit 1
  fi

  if [ -z "$EVALUATOR_COMMAND" ]; then
    printf 'Missing required config: evaluator.command\n' >&2
    exit 1
  fi

  if [ -z "$GENERATOR_TYPE" ]; then
    printf 'Missing required config: generator.type\n' >&2
    exit 1
  fi

  if [ -z "$EVALUATOR_TYPE" ]; then
    printf 'Missing required config: evaluator.type\n' >&2
    exit 1
  fi

  if ! jq -e '.generator.env? // {} | type == "object"' "$CONFIG_FILE" >/dev/null; then
    printf 'Invalid generator.env: expected object\n' >&2
    exit 1
  fi

  if ! jq -e '.evaluator.env? // {} | type == "object"' "$CONFIG_FILE" >/dev/null; then
    printf 'Invalid evaluator.env: expected object\n' >&2
    exit 1
  fi

  if ! jq -ne --arg type "$GENERATOR_TYPE" --argjson allowed "$allowed_agent_types" '$allowed | index($type) != null' >/dev/null; then
    printf 'Invalid generator.type: %s. Allowed values: opencode, claude, codex\n' "$GENERATOR_TYPE" >&2
    exit 1
  fi

  if ! jq -ne --arg type "$EVALUATOR_TYPE" --argjson allowed "$allowed_agent_types" '$allowed | index($type) != null' >/dev/null; then
    printf 'Invalid evaluator.type: %s. Allowed values: opencode, claude, codex\n' "$EVALUATOR_TYPE" >&2
    exit 1
  fi

  GENERATOR_STARTUP_COMMANDS="$(build_agent_startup_commands "generator" "$GENERATOR_TYPE" "$generator_env_json")"
  EVALUATOR_STARTUP_COMMANDS="$(build_agent_startup_commands "evaluator" "$EVALUATOR_TYPE" "$evaluator_env_json")"

  GENERATOR_COMMAND="$(build_agent_launch_command "$GENERATOR_TYPE" "$GENERATOR_COMMAND")"
  EVALUATOR_COMMAND="$(build_agent_launch_command "$EVALUATOR_TYPE" "$EVALUATOR_COMMAND")"

  debug_log "loaded config: maxRounds=$MAX_ROUNDS maxRepairCount=$MAX_REPAIR_COUNT generatorType=$GENERATOR_TYPE evaluatorType=$EVALUATOR_TYPE"
}

update_state() {
  local round="$1"
  local status="$2"
  local now
  now="$(iso_now)"
  local tmp
  tmp="$(mktemp)"
  jq --argjson round "$round" --arg status "$status" --arg updatedAt "$now" \
    '.round = $round | .status = $status | .updatedAt = $updatedAt' \
    "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

append_history_entry() {
  local now
  now="$(iso_now)"
  local tmp
  tmp="$(mktemp)"
  jq --arg prompt "$USER_PROMPT" --arg startedAt "$now" --arg updatedAt "$now" \
    '. += [{prompt: $prompt, rounds: [1], startedAt: $startedAt, updatedAt: $updatedAt}]' \
    "$HISTORY_FILE" > "$tmp"
  mv "$tmp" "$HISTORY_FILE"
}

append_round_to_history() {
  local round="$1"
  local now
  now="$(iso_now)"
  local tmp
  tmp="$(mktemp)"
  jq --argjson round "$round" --arg updatedAt "$now" '
    if length == 0 then .
    else .[-1].rounds |= (if index($round) then . else . + [$round] end)
      | .[-1].updatedAt = $updatedAt
    end
  ' "$HISTORY_FILE" > "$tmp"
  mv "$tmp" "$HISTORY_FILE"
}

update_history_timestamp() {
  local now
  now="$(iso_now)"
  local tmp
  tmp="$(mktemp)"
  jq --arg updatedAt "$now" 'if length == 0 then . else .[-1].updatedAt = $updatedAt end' \
    "$HISTORY_FILE" > "$tmp"
  mv "$tmp" "$HISTORY_FILE"
}

git_is_clean() {
  [ -z "$(git status --porcelain)" ]
}

confirm_discard_if_needed() {
  if git_is_clean; then
    return
  fi

  if [ "$CONFIRM_DISCARD" = "true" ]; then
    printf 'Worktree is dirty. Discard unstaged/uncommitted changes and continue? [y/N] '
    read -r answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *)
        printf 'Aborted. Please clean the worktree first.\n' >&2
        exit 1
        ;;
    esac
  fi

  git reset --hard HEAD >/dev/null 2>&1
  git clean -fd >/dev/null 2>&1
}

start_agent_pane() {
  local pane_id="$1"
  local command="$2"
  tmux send-keys -t "$pane_id" "$command" C-m
  debug_log "started pane $pane_id with command: $command"
}

init_agent_panes() {
  local pane_id
  pane_id="$(tmux split-window -v -b -d -c "$ROOT_DIR" -P -F '#{pane_id}' "$(build_agent_shell_bootstrap "$GENERATOR_STARTUP_COMMANDS")")"
  GENERATOR_PANE="$pane_id"
  pane_id="$(tmux split-window -h -d -t "$GENERATOR_PANE" -c "$ROOT_DIR" -P -F '#{pane_id}' "$(build_agent_shell_bootstrap "$EVALUATOR_STARTUP_COMMANDS")")"
  EVALUATOR_PANE="$pane_id"

  start_agent_pane "$GENERATOR_PANE" "$GENERATOR_COMMAND"
  start_agent_pane "$EVALUATOR_PANE" "$EVALUATOR_COMMAND"
}

send_to_pane() {
  local pane_id="$1"
  local message="$2"
  debug_log "sending message to pane $pane_id"
  tmux send-keys -t "$pane_id" "$message"
  sleep 1

  # tmux set-buffer -- "$message"
  # sleep 1
  # tmux paste-buffer -t "$pane_id"
  # sleep 1
  tmux send-keys -t "$pane_id" C-m

}

archive_round() {
  local round="$1"
  local archive_dir
  archive_dir="$ROUNDS_DIR/$(printf '%03d' "$round")"
  mkdir -p "$archive_dir"
  if [ -d "$CURRENT_DIR" ]; then
    mv "$CURRENT_DIR"/* "$archive_dir/" 2>/dev/null || true
  fi
  update_history_timestamp
  git add .gan
  git commit -m "doc(gan:r${round}): round archived" >/dev/null 2>&1 || true
  debug_log "archived round $round to $archive_dir"
}

notify_generator_for_round_start() {
  local round="$1"
  local prompt_msg
  printf -v prompt_msg "${PROMPTS[generator_round_start]}" "$USER_PROMPT" "$round"
  send_to_pane "$GENERATOR_PANE" "$prompt_msg"
}

notify_generator_for_contract_revision() {
  local round="$1"
  local prompt_msg
  printf -v prompt_msg "${PROMPTS[generator_contract_revision]}" "$round"
  send_to_pane "$GENERATOR_PANE" "$prompt_msg"
}

notify_generator_for_implementation() {
  local round="$1"
  local prompt_msg
  printf -v prompt_msg "${PROMPTS[generator_implementation]}" "$USER_PROMPT" "$round"
  send_to_pane "$GENERATOR_PANE" "$prompt_msg"
}

notify_generator_for_implement_revision() {
  local round="$1"
  local prompt_msg
  printf -v prompt_msg "${PROMPTS[generator_implement_revision]}" "$round"
  send_to_pane "$GENERATOR_PANE" "$prompt_msg"
}

notify_evaluator_for_contract() {
  local round="$1"
  local prompt_msg
  printf -v prompt_msg "${PROMPTS[evaluator_contract]}" "$USER_PROMPT" "$round"
  send_to_pane "$EVALUATOR_PANE" "$prompt_msg"
}

notify_evaluator_for_implementation() {
  local round="$1"
  local prompt_msg
  printf -v prompt_msg "${PROMPTS[evaluator_implementation]}" "$USER_PROMPT" "$round"
  send_to_pane "$EVALUATOR_PANE" "$prompt_msg"
}

handle_round_transition() {
  local round="$1"
  if [ "$round" -ge "$MAX_ROUNDS" ]; then
    printf 'Reached maxRounds=%s. Exiting.\n' "$MAX_ROUNDS"
    exit 0
  fi

  local next_round=$((round + 1))
  append_round_to_history "$next_round"
  update_state "$next_round" "ROUND_STARTED"
  git add .gan
  git commit -m "doc(gan:r${next_round}): round initialized" >/dev/null 2>&1 || true
  debug_log "initialized round $next_round and committed .gan state"
}

main() {
  ensure_gan_layout
  read_config
  confirm_discard_if_needed

  if [ "$(jq 'length' "$HISTORY_FILE")" -eq 0 ]; then
    append_history_entry
    git add .gan
    git commit -m "doc(gan): initialized history" >/dev/null 2>&1 || true
    debug_log "appended initial history entry"
  fi

  init_agent_panes

  sleep "$PANE_READY_SLEEP"
  debug_log "waited $PANE_READY_SLEEP seconds for panes to be ready"

  local last_notified=""
  local dirty_count=0

  while true; do
    local round status key
    round="$(jq -r '.round' "$STATE_FILE")"
    status="$(jq -r '.status' "$STATE_FILE")"
    key="$round:$status"
    debug_log "polled state: round=$round status=$status last_notified=${last_notified:-<empty>}"

    if [ "$key" = "$last_notified" ]; then
      debug_log "skip notify: state unchanged"
      sleep "$LOOP_SECONDS"
      continue
    fi

    if ! git_is_clean; then
      dirty_count=$((dirty_count + 1))
      debug_log "worktree dirty on poll $dirty_count/$DIRTY_LIMIT"
      printf 'Worktree is dirty. Waiting before notifying agents. (%s/%s)\n' "$dirty_count" "$DIRTY_LIMIT"
      if [ "$dirty_count" -ge "$DIRTY_LIMIT" ]; then
        printf 'Worktree stayed dirty for %s checks. Please clean the worktree and rerun.\n' "$DIRTY_LIMIT" >&2
        exit 1
      fi
      sleep "$LOOP_SECONDS"
      continue
    fi

    dirty_count=0

    case "$status" in
      ROUND_STARTED)
        debug_log "notify generator for round start"
        notify_generator_for_round_start "$round"
        ;;
      WAITING_FOR_CONTRACT_EVAL)
        debug_log "notify evaluator for contract review"
        notify_evaluator_for_contract "$round"
        ;;
      WAITING_FOR_CONTRACT_REVISION)
        debug_log "notify generator for contract revision"
        notify_generator_for_contract_revision "$round"
        ;;
      CONTRACT_APPROVED)
        debug_log "notify generator for implementation"
        notify_generator_for_implementation "$round"
        ;;
      WAITING_FOR_IMPLEMENT_EVAL)
        debug_log "notify evaluator for implementation review"
        notify_evaluator_for_implementation "$round"
        ;;
      WAITING_FOR_IMPLEMENT_REVISION)
        debug_log "notify generator for implementation revision"
        notify_generator_for_implement_revision "$round"
        ;;
      IMPLEMENT_APPROVED)
        debug_log "implementation approved, archive and transition round"
        update_state "$round" "ROUND_DONE"
        archive_round "$round"
        handle_round_transition "$round"
        last_notified=""
        sleep "$LOOP_SECONDS"
        continue
        ;;
      ROUND_FAILED_CONTRACT_LIMIT|ROUND_FAILED_IMPLEMENT_LIMIT)
        debug_log "round failed by limit, archive and transition round"
        archive_round "$round"
        handle_round_transition "$round"
        last_notified=""
        sleep "$LOOP_SECONDS"
        continue
        ;;
      ROUND_DONE)
        debug_log "round done, archive and transition round"
        archive_round "$round"
        handle_round_transition "$round"
        last_notified=""
        sleep "$LOOP_SECONDS"
        continue
        ;;
      *)
        printf 'Unknown status: %s\n' "$status" >&2
        exit 1
        ;;
    esac

    last_notified="$key"
    sleep "$LOOP_SECONDS"
  done
}

main
