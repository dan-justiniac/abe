#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$REPO_ROOT/platform/state.json"
WORKERS_DIR="$REPO_ROOT/platform/workers"
mkdir -p "$WORKERS_DIR"

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
  error "Platform state file missing. Run './scripts/setup-platform.sh' first."
fi

read_state_field() {
  local field="$1"
  python3 - "$STATE_FILE" "$field" <<'PY'
import json, sys
state_path, field = sys.argv[1], sys.argv[2]
with open(state_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get(field, ""))
PY
}

CONTAINER_NAME="$(read_state_field container)"
if [[ -z "$CONTAINER_NAME" ]]; then
  CONTAINER_NAME="abe-dev"
fi

WORKSPACE_REL="workspace-projects"
PROMPT=""
PROMPT_FILE_ARG=""
JOB_TIMEOUT=""
SHELL_TIMEOUT="300"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      if [[ $# -lt 2 ]]; then
        error "--dir requires a relative path"
      fi
      WORKSPACE_REL="$2"
      shift 2
      ;;
    --prompt)
      if [[ $# -lt 2 ]]; then
        error "--prompt requires text"
      fi
      PROMPT="$2"
      shift 2
      ;;
    --prompt-file)
      if [[ $# -lt 2 ]]; then
        error "--prompt-file requires a path or '-' for stdin"
      fi
      PROMPT_FILE_ARG="$2"
      shift 2
      ;;
    --timeout)
      if [[ $# -lt 2 ]]; then
        error "--timeout requires a positive number of seconds"
      fi
      JOB_TIMEOUT="$2"
      shift 2
      ;;
    --shell-timeout)
      if [[ $# -lt 2 ]]; then
        error "--shell-timeout requires a positive number of seconds"
      fi
      SHELL_TIMEOUT="$2"
      shift 2
      ;;
    --)
      shift
      PROMPT="$*"
      break
      ;;
    *)
      break
  esac
done

if [[ -n "$PROMPT_FILE_ARG" ]]; then
  if [[ "$PROMPT_FILE_ARG" == "-" ]]; then
    PROMPT="$(cat)"
  else
    if [[ ! -f "$PROMPT_FILE_ARG" ]]; then
      error "Prompt file '$PROMPT_FILE_ARG' not found"
    fi
    PROMPT="$(cat "$PROMPT_FILE_ARG")"
  fi
elif [[ -z "$PROMPT" ]]; then
  if [[ -t 0 ]]; then
    error "Provide worker instructions via --prompt, --prompt-file, or stdin."
  fi
  PROMPT="$(cat)"
fi

PROMPT="${PROMPT%$'\n'}"
if [[ -z "$PROMPT" ]]; then
  error "Prompt cannot be empty."
fi

WORKSPACE_REL="${WORKSPACE_REL#./}"
if [[ "$WORKSPACE_REL" == /* ]]; then
  error "Workspace must be a relative path inside the repo (got '$WORKSPACE_REL')."
fi

WORKSPACE_ABS="$(python3 - "$REPO_ROOT" "$WORKSPACE_REL" <<'PY'
import os, sys
root, rel = sys.argv[1], sys.argv[2]
abs_path = os.path.abspath(os.path.join(root, rel))
if os.path.commonpath([root, abs_path]) != root:
    raise SystemExit(1)
print(abs_path)
PY
)" || error "Workspace path escapes repository."
mkdir -p "$WORKSPACE_ABS"

JOB_ID="worker-$(date +%Y%m%d-%H%M%S)-$RANDOM"
PROMPT_PATH="$WORKERS_DIR/$JOB_ID.prompt"
RUNNER_PATH="$WORKERS_DIR/$JOB_ID.sh"
META_PATH="$WORKERS_DIR/$JOB_ID.json"
PID_PATH="$WORKERS_DIR/$JOB_ID.pid"
STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LOG_REL="platform/workers/$JOB_ID.log"
PID_REL="platform/workers/$JOB_ID.pid"
RUNNER_REL="platform/workers/$JOB_ID.sh"
SUMMARY_REL="platform/workers/$JOB_ID.summary"

printf '%s\n' "$PROMPT" >"$PROMPT_PATH"

cat >"$RUNNER_PATH" <<EOF
#!/usr/bin/env bash
set -uo pipefail

JOB_ID="$JOB_ID"
WORKSPACE_REL="$WORKSPACE_REL"
PROMPT_FILE="/workspace/platform/workers/$JOB_ID.prompt"
LOG_REL="$LOG_REL"
SUMMARY_REL="$SUMMARY_REL"
JOB_TIMEOUT="$JOB_TIMEOUT"
SHELL_TIMEOUT="$SHELL_TIMEOUT"
STARTED_AT="$STARTED_AT"

log() {
  printf '[%s] %s\n' "\$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "\$1"
}

log "Worker \$JOB_ID starting in /workspace/\$WORKSPACE_REL"
cd "/workspace/\$WORKSPACE_REL"

PROMPT_CONTENT="\$(cat "\$PROMPT_FILE")"
if [[ -n "\$JOB_TIMEOUT" ]]; then
  set +e
  timeout "\$JOB_TIMEOUT" codex exec -c shell_command_timeout_seconds="\$SHELL_TIMEOUT" --sandbox workspace-write -- "\$PROMPT_CONTENT"
  STATUS=\$?
  set -e
  if [[ \$STATUS -eq 124 ]]; then
    log "Worker \$JOB_ID hit timeout (\$JOB_TIMEOUT seconds)"
  fi
else
  set +e
  codex exec -c shell_command_timeout_seconds="\$SHELL_TIMEOUT" --sandbox workspace-write -- "\$PROMPT_CONTENT"
  STATUS=\$?
  set -e
fi
if [[ \$STATUS -ne 0 ]]; then
  log "Worker \$JOB_ID failed with status \$STATUS"
else
  log "Worker \$JOB_ID completed successfully"
fi

FINISHED_AT="\$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LOG_FILE="/workspace/$LOG_REL"
SUMMARY_FILE="/workspace/$SUMMARY_REL"
mkdir -p "\$(dirname "\$SUMMARY_FILE")"

{
  echo "Job: \$JOB_ID"
  echo "Workspace: /workspace/\$WORKSPACE_REL"
  echo "State: \$([[ \$STATUS -eq 0 ]] && echo completed || echo failed)"
  echo "Exit code: \$STATUS"
  if [[ -n "\$JOB_TIMEOUT" ]]; then
    echo "Timeout (s): \$JOB_TIMEOUT"
  fi
  echo "Started: \$STARTED_AT"
  echo "Finished: \$FINISHED_AT"
  echo
  echo "Prompt:"
  cat "\$PROMPT_FILE"
  echo
  echo "--- Last 40 log lines ---"
  if [[ -f "\$LOG_FILE" ]]; then
    tail -n 40 "\$LOG_FILE"
  else
    echo "(log not found)"
  fi
} > "\$SUMMARY_FILE"

WORKER_STATUS="\$STATUS" JOB_ID="\$JOB_ID" FINISHED_AT="\$FINISHED_AT" python3 - <<'PY'
import json, os, datetime, pathlib
status = int(os.environ["WORKER_STATUS"])
job_id = os.environ["JOB_ID"]
finished_at = os.environ["FINISHED_AT"]
meta_path = pathlib.Path("/workspace/platform/workers") / f"{job_id}.json"
try:
    with meta_path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
except FileNotFoundError:
    data = {"job_id": job_id}
data["state"] = "completed" if status == 0 else "failed"
data["finished_at"] = finished_at
data["exit_code"] = status
with meta_path.open("w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
PY

exit \$STATUS
EOF
chmod +x "$RUNNER_PATH"

python3 - "$META_PATH" "$JOB_ID" "$WORKSPACE_REL" "$CONTAINER_NAME" "$LOG_REL" "$PID_REL" "$RUNNER_REL" "$PROMPT_PATH" "$STARTED_AT" "$SUMMARY_REL" "$JOB_TIMEOUT" <<'PY'
import json, sys, pathlib
meta_path, job_id, workspace_rel, container, log_rel, pid_rel, runner_rel, prompt_path, started_at, summary_rel, timeout = sys.argv[1:]
prompt_text = pathlib.Path(prompt_path).read_text(encoding="utf-8")
preview = " ".join(prompt_text.strip().split())
if len(preview) > 200:
    preview = preview[:197] + "..."
data = {
    "job_id": job_id,
    "workspace": workspace_rel,
    "container": container,
    "log_file": log_rel,
    "pid_file": pid_rel,
    "runner": runner_rel,
    "prompt_file": f"platform/workers/{pathlib.Path(prompt_path).name}",
    "summary_file": summary_rel,
    "prompt_preview": preview,
    "state": "launching",
    "started_at": started_at,
    "finished_at": None,
    "exit_code": None,
    "timeout_seconds": int(timeout) if timeout else None,
}
with open(meta_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
PY

docker exec "$CONTAINER_NAME" bash -lc "cd /workspace && nohup /workspace/platform/workers/$JOB_ID.sh >> /workspace/$LOG_REL 2>&1 & echo \$! > /workspace/$PID_REL"

if [[ ! -f "$PID_PATH" ]]; then
  error "Failed to launch worker inside container (PID file missing)."
fi

PID="$(tr -d '\n' <"$PID_PATH")"
python3 - "$META_PATH" "$PID" <<'PY'
import json, sys
meta_path, pid = sys.argv[1:]
with open(meta_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["pid"] = int(pid)
data["state"] = "running"
with open(meta_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
PY

echo "Worker $JOB_ID launched for workspace '$WORKSPACE_REL' (PID $PID)."
echo "Log file: $LOG_REL"
echo "Check status with: ./scripts/worker-status.sh $JOB_ID"
