#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
WORKERS_DIR = REPO_ROOT / "platform" / "workers"


def run(cmd):
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        print(result.stderr.strip())
    else:
        print(result.stdout.strip())


def main(job_id: str):
    meta_path = WORKERS_DIR / f"{job_id}.json"
    if not meta_path.exists():
        print(f"[ERROR] Worker '{job_id}' not found.")
        sys.exit(1)

    meta = json.loads(meta_path.read_text())
    workspace = meta.get("workspace")
    container = meta.get("container", "abe-dev")
    log_rel = meta.get("log_file")
    summary_rel = meta.get("summary_file")
    prompt_rel = meta.get("prompt_file")

    print(f"=== Worker Report: {job_id} ===")
    print(f"Workspace: {workspace}")
    print(f"State: {meta.get('state')} (exit code: {meta.get('exit_code')})")
    print(f"Started: {meta.get('started_at')}")
    print(f"Finished: {meta.get('finished_at')}")
    print()

    if prompt_rel:
        prompt_path = REPO_ROOT / prompt_rel
        if prompt_path.exists():
            print("--- Prompt ---")
            print(prompt_path.read_text())
            print()

    if summary_rel:
        summary_path = REPO_ROOT / summary_rel
        if summary_path.exists():
            print("--- Summary ---")
            print(summary_path.read_text())
            print()

    if log_rel:
        log_path = REPO_ROOT / log_rel
        if log_path.exists():
            print("--- Last 40 Log Lines ---")
            lines = log_path.read_text().splitlines()
            for line in lines[-40:]:
                print(line)
            print()

    if workspace:
        print("--- Git Status ---")
        run(
            [
                "docker",
                "exec",
                container,
                "bash",
                "-lc",
                f"cd /workspace/{workspace} && git status -sb",
            ]
        )
        print()
        print("--- Git Diff Summary ---")
        run(
            [
                "docker",
                "exec",
                container,
                "bash",
                "-lc",
                f"cd /workspace/{workspace} && git diff --stat",
            ]
        )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: collect-worker-report.sh <job-id>")
        sys.exit(1)
    main(sys.argv[1])
