#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$REPO_ROOT/platform/state.json"
DEFAULT_REL_PATH="workspace-projects"
CONTAINER_DEFAULT="abe-dev"

error() {
  echo "[ERROR] $1" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Command '$1' not found. Install it and retry."
  fi
}

require_cmd docker
require_cmd python3

if [[ ! -f "$STATE_FILE" ]]; then
  error "Platform state file not found. Run './scripts/setup-platform.sh' first."
fi

read_state_field() {
  local field="$1"
  python3 - "$STATE_FILE" "$field" <<'PY'
import json, sys
path, field = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get(field, ""))
PY
}

CONTAINER_NAME="$(read_state_field container)"
if [[ -z "$CONTAINER_NAME" ]]; then
  CONTAINER_NAME="$CONTAINER_DEFAULT"
fi

TARGET_REL="$DEFAULT_REL_PATH"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      if [[ $# -lt 2 ]]; then
        error "--dir requires a relative path"
      fi
      TARGET_REL="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
  esac
done

CODEX_ARGS=("$@")

if [[ -z "$TARGET_REL" ]]; then
  TARGET_REL="$DEFAULT_REL_PATH"
fi

if [[ "$TARGET_REL" == /* ]]; then
  error "Provide a relative path inside the repo (got '$TARGET_REL')."
fi

RESOLVED_PATH="$(python3 - "$REPO_ROOT" "$TARGET_REL" <<'PY'
import os, sys
root = os.path.abspath(sys.argv[1])
rel = sys.argv[2]
path = os.path.abspath(os.path.join(root, rel))
if os.path.commonpath([root, path]) != root:
    sys.exit(1)
print(path)
PY
)" || error "Target directory must live inside the repo."

mkdir -p "$RESOLVED_PATH"

if ! docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  error "Container '$CONTAINER_NAME' is missing. Re-run './scripts/setup-platform.sh'."
fi

if ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  docker start "$CONTAINER_NAME" >/dev/null
fi

escaped_rel="$(printf '%q' "$TARGET_REL")"
codex_cmd="codex --sandbox workspace-write -a on-request"
if [[ ${#CODEX_ARGS[@]} -gt 0 ]]; then
  for arg in "${CODEX_ARGS[@]}"; do
    codex_cmd+=" $(printf '%q' "$arg")"
  done
fi

container_cmd="cd /workspace && mkdir -p $escaped_rel && cd $escaped_rel && $codex_cmd"
docker_args=(-i)
if [[ -t 1 ]]; then
  docker_args=(-it)
fi
exec docker exec "${docker_args[@]}" "$CONTAINER_NAME" bash -lc "$container_cmd"
