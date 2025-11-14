#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
if [[ -d /dev/fd ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
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
  if ! colima status >/dev/null 2>&1; then
    colima start "${COLIMA_ARGS[@]}"
  fi
else
  announce "Non-macOS host detected ($OS). Assuming docker is already running."
fi

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

current_label=""
current_image=""
if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  current_label="$(docker inspect -f "{{ index .Config.Labels \"$IMAGE_LABEL_KEY\" }}" "$CONTAINER_NAME" 2>/dev/null || echo "")"
  current_image="$(docker inspect -f '{{ .Config.Image }}' "$CONTAINER_NAME" 2>/dev/null || echo "")"
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
fi

announce "Ensuring container '$CONTAINER_NAME' exists"
if [[ -z "$current_label" ]]; then
  docker run -d --name "$CONTAINER_NAME" \
    --hostname "$CONTAINER_NAME" \
    --restart unless-stopped \
    --label "$IMAGE_LABEL_KEY=$PLATFORM_IMAGE" \
    -v "$HOME/.codex:/root/.codex" \
    "$PLATFORM_IMAGE"
fi

announce "Ensuring container '$CONTAINER_NAME' is running"
if ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  docker start "$CONTAINER_NAME"
fi

run_in_container() {
  docker exec "$CONTAINER_NAME" bash -lc "$1"
}

announce "Verifying container Codex login status"
run_in_container "codex login status"

announce "Platform ready. Container '$CONTAINER_NAME' is running $PLATFORM_IMAGE"
announce "Logs saved to $LOG_FILE"
