#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
WORKERS_DIR = REPO_ROOT / "platform" / "workers"


def load_metadata():
    files = sorted(WORKERS_DIR.glob("*.json"))
    metas = []
    for path in files:
        try:
            with path.open("r", encoding="utf-8") as fh:
                data = json.load(fh)
        except (json.JSONDecodeError, OSError):
            continue
        data["_meta_path"] = path
        metas.append(data)
    return metas


def refresh_state(meta):
    state = meta.get("state")
    if state not in {"running", "launching"}:
        return False
    pid_file = meta.get("pid_file")
    container = meta.get("container")
    if not pid_file or not container:
        return False
    pid_path = REPO_ROOT / pid_file
    if not pid_path.exists():
        return False
    pid = pid_path.read_text(encoding="utf-8").strip()
    if not pid:
        return False
    cmd = [
        "docker",
        "exec",
        container,
        "bash",
        "-lc",
        f"kill -0 {pid} >/dev/null 2>&1",
    ]
    result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode == 0:
        if state != "running":
            meta["state"] = "running"
            return True
        return False
    return False


def save_meta(meta):
    path = meta.get("_meta_path")
    if not path:
        return
    payload = {k: v for k, v in meta.items() if not k.startswith("_")}
    with path.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2)


def format_table(metas):
    header = f"{'JOB ID':<28} {'STATE':<10} {'WORKSPACE':<30} {'STARTED (UTC)':<20} {'FINISHED (UTC)':<20}"
    lines = [header]
    for meta in metas:
        lines.append(
            f"{meta.get('job_id',''):<28} "
            f"{(meta.get('state') or ''):<10} "
            f"{(meta.get('workspace') or ''):<30} "
            f"{(meta.get('started_at') or ''):<20} "
            f"{(meta.get('finished_at') or '-'):<20}"
        )
    return "\n".join(lines)


def read_log(meta):
    log_file = meta.get("log_file")
    if not log_file:
        return None
    path = REPO_ROOT / log_file
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8", errors="replace")


def main():
    parser = argparse.ArgumentParser(description="Inspect Codex worker jobs")
    parser.add_argument("job_id", nargs="?", help="Job ID to inspect (default: list all)")
    parser.add_argument("--latest", action="store_true", help="Show the most recent job")
    parser.add_argument("--json", action="store_true", help="Output raw JSON for the selected job")
    parser.add_argument("--tail", type=int, default=0, help="Show the last N log lines for the selected job")
    parser.add_argument("--log", action="store_true", help="Print the entire log for the selected job")
    args = parser.parse_args()

    if not WORKERS_DIR.exists():
        print("No worker records found.")
        return

    metas = load_metadata()
    if not metas:
        print("No worker records found.")
        return

    updated = False
    for meta in metas:
        if refresh_state(meta):
            save_meta(meta)
            updated = True
    if updated:
        metas = load_metadata()

    if not args.job_id and not args.latest and not args.log and args.tail == 0:
        print(format_table(metas))
        return

    target_meta = None
    if args.job_id:
        for meta in metas:
            if meta.get("job_id") == args.job_id:
                target_meta = meta
                break
        if not target_meta:
            print(f"No worker found with id '{args.job_id}'.")
            return
    else:
        target_meta = max(
            metas,
            key=lambda m: m.get("started_at") or "",
        )

    if args.json:
        payload = {k: v for k, v in target_meta.items() if not k.startswith("_")}
        print(json.dumps(payload, indent=2))
        return

    print(f"Job: {target_meta.get('job_id')}")
    print(f"Workspace: {target_meta.get('workspace')}")
    print(f"State: {target_meta.get('state')} (exit code: {target_meta.get('exit_code')})")
    print(f"Container: {target_meta.get('container')}")
    print(f"Started: {target_meta.get('started_at')}")
    print(f"Finished: {target_meta.get('finished_at')}")
    print(f"Log: {target_meta.get('log_file')}")
    summary_rel = target_meta.get("summary_file")
    if summary_rel:
        print(f"Summary: {summary_rel}")
    print(f"Prompt preview: {target_meta.get('prompt_preview')}")

    log_text = read_log(target_meta)
    if log_text is None:
        print("Log not found.")
        return

    if args.log:
        print("\n--- Worker Log ---")
        print(log_text, end="" if log_text.endswith("\n") else "\n")
        return

    tail_lines = args.tail if args.tail > 0 else 20
    lines = log_text.splitlines()
    selected = lines[-tail_lines :] if len(lines) >= tail_lines else lines
    print(f"\n--- Last {len(selected)} log lines ---")
    for line in selected:
        print(line)


if __name__ == "__main__":
    main()
