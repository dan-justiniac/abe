#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Cleaning workspace-projects/..."
rm -rf "$REPO_ROOT"/workspace-projects/*
mkdir -p "$REPO_ROOT/workspace-projects"

echo "Cleaning platform/workers/..."
rm -rf "$REPO_ROOT"/platform/workers/*
mkdir -p "$REPO_ROOT/platform/workers"

echo "Re-running platform setup..."
exec "$SCRIPT_DIR/setup-platform.sh"
