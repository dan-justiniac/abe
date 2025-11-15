#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKERS_DIR="$REPO_ROOT/platform/workers"

usage() {
  echo "Usage: $0 <job-id> [--force]" >&2
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

JOB_ID="$1"
shift
FORCE=false
if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--force" ]]; then
    FORCE=true
  else
    usage
  fi
fi

META_PATH="$WORKERS_DIR/$JOB_ID.json"
if [[ ! -f "$META_PATH" ]]; then
  echo "[ERROR] Worker '$JOB_ID' not found." >&2
  exit 1
fi

container="$(python3 - "$META_PATH" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("container", ""))
PY
)"

if [[ -z "$container" ]]; then
  echo "[ERROR] Container name missing in metadata." >&2
  exit 1
fi

PID_FILE_REL="$(python3 - "$META_PATH" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("pid_file") or "")
PY
)"

if [[ -z "$PID_FILE_REL" ]]; then
  echo "[ERROR] PID file not recorded for worker '$JOB_ID'." >&2
  exit 1
fi

PID_FILE="$REPO_ROOT/$PID_FILE_REL"
if [[ ! -f "$PID_FILE" ]]; then
  echo "[WARN] PID file missing; worker may already be stopped." >&2
  exit 0
fi
PID="$(tr -d '\n' <"$PID_FILE")"
if [[ -z "$PID" ]]; then
  echo "[ERROR] PID file empty." >&2
  exit 1
fi

SIGNAL="TERM"
if [[ "$FORCE" == true ]]; then
  SIGNAL="KILL"
fi

echo "Stopping worker $JOB_ID (PID $PID) with SIG$SIGNAL..."
if ! docker exec "$container" bash -lc "kill -s $SIGNAL $PID" >/dev/null 2>&1; then
  echo "[WARN] Failed to signal PID $PID; it may already be gone." >&2
fi

python3 - "$META_PATH" <<'PY'
import json, sys, datetime
meta_path = sys.argv[1]
with open(meta_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["state"] = "failed"
data["exit_code"] = -9
data["finished_at"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with open(meta_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
PY

rm -f "$PID_FILE"
echo "Worker $JOB_ID marked as failed."
