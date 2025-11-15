#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$REPO_ROOT/platform/state.json"
mkdir -p "$(dirname "$STATE_FILE")"
WORKSPACES_DIR="$REPO_ROOT/workspace-projects"
mkdir -p "$WORKSPACES_DIR"
if [[ -d /dev/fd ]]; then
  set +e
  exec > >(tee -a "$LOG_FILE") 2>&1
  tee_status=$?
  set -e
  if [[ $tee_status -ne 0 ]]; then
    echo "Process substitution unavailable (permission denied). Logging directly to $LOG_FILE"
    exec >>"$LOG_FILE" 2>&1
  fi
else
  echo "Logging directly to $LOG_FILE (process substitution unavailable)"
  exec >>"$LOG_FILE" 2>&1
fi

COLIMA_ARGS=(--vm-type vz --arch aarch64 --cpu 8 --memory 24 --disk 120 --mount-type virtiofs --runtime docker)
CONTAINER_NAME="abe-dev"
PLATFORM_IMAGE="danjustiniac/abe-platform:v0.0.1"
IMAGE_LABEL_KEY="abe.platform.image"

announce() {
  echo "==> $1"
}

error() {
  echo "[ERROR] $1" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Command '$1' not found. Install it and re-run this script."
  fi
}

require_cmd docker
require_cmd codex

OS="$(uname -s)"
if [[ "$OS" == "Darwin" ]]; then
  require_cmd colima
  announce "Ensuring Colima is running"
else
  announce "Non-macOS host detected ($OS). Assuming docker is already running."
fi

handle_colima_error() {
  local message="$1"
  if grep -qi "operation not permitted" <<<"$message"; then
    error "Colima requires access to $HOME/.colima. Run this script directly on the host or launch Codex with '--add-dir $HOME/.colima'. Original error: $message"
  fi
  printf '%s\n' "$message" >&2
  error "Colima command failed"
}

ensure_colima_running() {
  if [[ "$OS" != "Darwin" ]]; then
    return
  fi

  local status_output
  if status_output=$(colima status 2>&1); then
    return
  fi

  if ! grep -qi "is not running" <<<"$status_output"; then
    handle_colima_error "$status_output"
  fi

  announce "Starting Colima with required resources"
  local start_output
  if ! start_output=$(colima start "${COLIMA_ARGS[@]}" 2>&1); then
    handle_colima_error "$start_output"
  fi
}

ensure_colima_running

announce "Waiting for Docker daemon"
for i in {1..30}; do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [[ $i -eq 30 ]]; then
    error "Docker daemon not responding"
  fi
  announce "Docker not ready yet, retrying ($i)"
done

if ! codex login status >/dev/null 2>&1; then
  error "Codex is not logged in on the host. Run 'codex login' once, then re-run this script."
fi

if [[ ! -d "$HOME/.codex" ]]; then
  error "Host Codex credentials directory ($HOME/.codex) is missing."
fi

announce "Pulling platform image $PLATFORM_IMAGE"
docker pull "$PLATFORM_IMAGE"

container_exists=false
current_label=""
current_image=""
current_repo_mount=""
if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  container_exists=true
  current_label="$(docker inspect -f "{{ index .Config.Labels \"$IMAGE_LABEL_KEY\" }}" "$CONTAINER_NAME" 2>/dev/null || echo "")"
  current_image="$(docker inspect -f '{{ .Config.Image }}' "$CONTAINER_NAME" 2>/dev/null || echo "")"
  current_repo_mount="$(docker inspect -f '{{ range .Mounts }}{{ if eq .Destination "/workspace" }}{{ .Source }}{{ end }}{{ end }}' "$CONTAINER_NAME" 2>/dev/null || echo "")"
fi

if [[ "$current_label" == "<no value>" ]]; then
  current_label=""
fi

if [[ -n "$current_label" && "$current_label" != "$PLATFORM_IMAGE" ]]; then
  announce "Container uses different labeled image ($current_label). Recreating..."
  docker rm -f "$CONTAINER_NAME"
  current_label=""
  current_image=""
fi

if [[ -n "$current_image" && "$current_image" != "$PLATFORM_IMAGE" ]]; then
  announce "Container was created from $current_image. Recreating..."
  docker rm -f "$CONTAINER_NAME"
  current_label=""
  current_image=""
  current_repo_mount=""
fi

if [[ "$container_exists" == true && "$current_repo_mount" != "$REPO_ROOT" ]]; then
  announce "Container repo mount ($current_repo_mount) differs from $REPO_ROOT. Recreating..."
  docker rm -f "$CONTAINER_NAME"
  current_label=""
  current_image=""
  current_repo_mount=""
fi

announce "Ensuring container '$CONTAINER_NAME' exists"
if [[ -z "$current_label" ]]; then
  docker run -d --name "$CONTAINER_NAME" \
    --hostname "$CONTAINER_NAME" \
    --restart unless-stopped \
    --label "$IMAGE_LABEL_KEY=$PLATFORM_IMAGE" \
    -v "$REPO_ROOT:/workspace" \
    -v "$HOME/.codex:/root/.codex" \
    -w /workspace \
    "$PLATFORM_IMAGE"
fi

announce "Ensuring container '$CONTAINER_NAME' is running"
if ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  docker start "$CONTAINER_NAME"
fi

run_in_container() {
  docker exec "$CONTAINER_NAME" bash -lc "$1"
}

write_state_file() {
  cat >"$STATE_FILE" <<EOF
{
  "container": "$CONTAINER_NAME",
  "repo_root": "$REPO_ROOT",
  "platform_image": "$PLATFORM_IMAGE",
  "log_file": "$LOG_FILE",
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

announce "Verifying container Codex login status"
run_in_container "codex login status"

announce "Platform ready. Container '$CONTAINER_NAME' is running $PLATFORM_IMAGE"

announce "Launching Codex welcome check"
if ! codex --sandbox workspace-write --add-dir "$HOME/.colima" exec -- "printf 'Welcome to ABE! Colima and abe-dev are ready. Next step: docker exec -it abe-dev bash\n'"; then
  echo "Codex welcome check failed. Run 'codex --sandbox workspace-write --add-dir \"$HOME/.colima\" exec -- echo \"ABE ready\"' manually if needed."
fi

write_state_file

announce "Logs saved to $LOG_FILE"
