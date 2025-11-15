#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME=${CONTAINER_NAME:-abe-dev}
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <command> [args...]" >&2
  exit 1
fi

escaped_cmd=""
for arg in "$@"; do
  if [[ -z "$escaped_cmd" ]]; then
    escaped_cmd="$(printf '%q' "$arg")"
  else
    escaped_cmd+=" $(printf '%q' "$arg")"
  fi
done

exec docker exec "$CONTAINER_NAME" bash -lc "cd /workspace && $escaped_cmd"
