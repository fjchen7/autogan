#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULES_SOURCE_DIR="$ROOT_DIR/gan/rules"
AUTOGAN_SOURCE="$ROOT_DIR/autogan.sh"

show_help() {
  cat <<'EOF'
Install autogan into the target directory by creating .gan and autogan.sh.

Usage:
  install.sh
  install.sh [--dir <target-dir> | -d <target-dir>]
  install.sh --help

Options:
  --dir, -d <target-dir>  Set the target project directory.
                          Default: the current working directory.
  --help                  Show this help message.
EOF
}

ensure_file() {
  local file="$1"
  local content="$2"

  if [ ! -f "$file" ]; then
    printf '%s\n' "$content" > "$file"
  fi
}

write_default_config() {
  local file="$1"

  cat > "$file" <<'EOF'
{
  "maxRounds": 10,
  "maxRepairCount": 3,
  "confirmDiscardOnRestart": true,
  "generator": {
    "command": "opencode",
    "env": {
      "OPENCODE_PERMISSION": {
        "*": "allow"
      }
    },
    "type": "opencode"
  },
  "evaluator": {
    "command": "claude --dangerously-skip-permissions",
    "env": {},
    "type": "claude"
  }
}
EOF
}

init_gan_dir() {
  local target_dir="$1"
  local gan_dir="$target_dir/.gan"
  local current_dir="$gan_dir/current"
  local rounds_dir="$gan_dir/rounds"
  local rules_dir="$gan_dir/rules"
  local config_file="$gan_dir/config.json"
  local state_file="$gan_dir/state.json"
  local history_file="$gan_dir/history.json"
  local summary_file="$gan_dir/summary.json"
  local autogan_target="$target_dir/autogan.sh"

  if [ -e "$gan_dir" ]; then
    printf 'Target already contains .gan: %s\n' "$gan_dir" >&2
    exit 1
  fi

  if [ ! -d "$RULES_SOURCE_DIR" ]; then
    printf 'Missing rules source directory: %s\n' "$RULES_SOURCE_DIR" >&2
    exit 1
  fi

  if [ ! -f "$AUTOGAN_SOURCE" ]; then
    printf 'Missing autogan.sh source: %s\n' "$AUTOGAN_SOURCE" >&2
    exit 1
  fi

  mkdir -p "$target_dir" "$gan_dir" "$current_dir" "$rounds_dir" "$rules_dir"
  cp -R "$RULES_SOURCE_DIR"/. "$rules_dir/"
  cp "$AUTOGAN_SOURCE" "$autogan_target"
  chmod +x "$autogan_target"
  write_default_config "$config_file"

  ensure_file "$state_file" '{
  "round": 1,
  "status": "ROUND_STARTED",
  "updatedAt": "1970-01-01T00:00:00Z"
}'
  ensure_file "$history_file" '[]'
  ensure_file "$summary_file" '[]'

  printf 'Installed autogan into %s\n' "$target_dir"
  printf 'Created %s\n' "$gan_dir"
  printf 'Copied rules to %s\n' "$rules_dir"
  printf 'Copied autogan.sh to %s\n' "$autogan_target"
}

main() {
  local target_dir="$(pwd)"

  if [ $# -ge 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
    show_help
    exit 0
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --dir|-d)
        if [ $# -lt 2 ]; then
          printf 'Missing value for %s\n' "$1" >&2
          exit 1
        fi
        target_dir="$2"
        shift 2
        ;;
      *)
        show_help >&2
        exit 1
        ;;
    esac
  done

  init_gan_dir "$target_dir"
}

main "$@"
