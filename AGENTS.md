# Agent Guide (Top-Level Codex)

This file is for the Codex agent that maintains the ABE platform repository itself. All canonical operational instructions live in `README.md`; refer to that doc for the latest bootstrap steps, helper scripts, and workflows. Use this guide as a quick checklist so you can get to work immediately.

## Responsibilities
- Keep `platform/`, `scripts/`, and `README.md` healthy so humans and nested agents can spin up the environment without friction.
- Leave application code for the Codex agent that runs _inside_ the platform container (see “Nested Codex Sessions” below).
- Record any new bootstrap requirements only once (in `README.md`). Update this guide if the expectations for the top-level agent change.

## Daily Flow
1. Run `./scripts/setup-platform.sh` (see `README.md` → Quick Start) or confirm `platform/state.json` already exists.
2. Verify Colima/Docker/Codex per `README.md` (“Verification Commands”) before editing files.
3. Use `./scripts/run-in-platform.sh <cmd>` for any prep inside `abe-dev` (cloning into `workspace-projects/`, installing deps, etc.). For compound commands, pass `-- "cd workspace-projects && git clone …"`.
4. When delegating work, launch a worker with `./scripts/launch-worker.sh --dir workspace-projects/<repo> --prompt-file prompt.md --timeout 600` (or pipe instructions via stdin). The helper records logs/summaries under `platform/workers/` and returns immediately with a job ID so the user keeps control of the host session.
5. Answer “status?” questions via `./scripts/worker-status.sh <job-id>` (now shows the last log lines automatically) or `./scripts/collect-worker-report.sh <job-id>`. Use `./scripts/kill-worker.sh <job-id>` if a worker is stuck.

## Nested Codex Sessions
- External repositories should live under `workspace-projects/` (ignored by git).
- Prefer the asynchronous workflow: `launch-worker.sh` to start jobs, `worker-status.sh` / `collect-worker-report.sh` to monitor them, `kill-worker.sh` to stop them. Use `./scripts/platform-codex.sh` only when you need an interactive shell inside the container.
- The top-level Codex should only touch this repo unless specifically asked to inspect the other workspace.

## Coding & Process Notes
- Source layout, testing defaults, and commit conventions match the sections in `README.md`. Follow those instructions when adding new code or docs.
- Keep this guide concise. If a new process emerges, update `README.md` first, then summarize or link to it here.
