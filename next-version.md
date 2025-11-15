# Next-Version Concept: Responsive Worker Delegation

This document proposes platform and workflow changes to address the issues captured in `user-report.md` and `codex-report.md`. The goal is to make host Codex sessions responsive (return immediately after delegating) while still giving the user visibility and reducing approval fatigue.

## Pain Points (from reports)
- **Blocking host session**: The user lost access to the host Codex until the worker was done. CodexReport shows the host waited on long `codex exec` runs that hit timeouts.
- **Approval fatigue**: Every command inside the container required user confirmation. Host commands (`run-in-platform.sh`, `platform-codex.sh`) were issued directly from the host session, so the CLI kept requesting approvals.
- **Status ambiguity**: User did not know whether the worker even launched, let alone how it progressed. CodexReport confirms no mid-flight status updates.

## Target Experience
1. Host Codex asks for the task and target repo.
2. Host launches a worker asynchronously and immediately returns control to the user.
3. All container work runs without per-command user approvals.
4. Host can answer “status?” queries instantly because it tracks each worker session.
5. Completion summary (success/failure) is delivered proactively once the worker finishes.

## Proposed Approach

### 1. Non-blocking worker launcher
- Add a helper script (e.g. `scripts/launch-worker.sh`) that:
  - Accepts a prompt file or string plus a workspace path.
  - Starts `codex exec` in the background (inside the container via `docker exec`) and streams logs to `workspace/.codex-worker/log.txt`.
  - Returns immediately to the host Codex with a job ID.
- Host Codex runs this script, captures the ID, and reports: “Worker abe-smoke#1 launched; ask for status anytime.”

### 2. Worker registry & status command
- Maintain a lightweight JSON registry under `platform/workers/*.json` (ignored by git) storing:
  - job id, workspace path, prompt summary, start time, pid, log path, and current state (`running`, `failed`, `completed`).
- Provide `scripts/worker-status.sh [job-id|--latest]` to query the registry, tail logs, or detect exited processes.
- Host Codex uses this command to answer user “status?” queries without reentering the container.

### 3. Default approvals & sandboxing
- Run all platform-management scripts with `codex --sandbox workspace-write --add-dir ~/.colima -a on-request` so commands touching the container (e.g., cloning, launching workers) do not require additional user approval; only host-level file edits in this repo still prompt as usual.
- Document that `run-in-platform.sh` and the new launchers are considered “trusted” operations once the initial bootstrap succeeds.

### 4. Systematic status updates
- Host Codex workflow:
  1. Confirm prerequisites (README Quick Start).
  2. Prepare workspace (`run-in-platform.sh bash -lc 'cd workspace-projects && ...'`), logging key steps but batching commands to reduce approvals.
  3. Launch worker via `launch-worker.sh`, capture job ID, and immediately respond to the user.
  4. Set a reminder (internal note) to poll `worker-status.sh` periodically and notify the user when state changes.
- The worker log file should include major milestones (clone started, npm install, tests) so status queries yield meaningful info without spamming the user by default.

### 5. Handling network/timeout failures
- `launch-worker.sh` should enforce a per-step timeout and fail fast if network calls (like `npm install`) hang, writing the error to the log and marking the job as `failed`.
- Host Codex uses this signal to alert the user promptly rather than waiting for manual inspection.

## Rollout Steps
1. Implement `launch-worker.sh` and `worker-status.sh`, ensure they use background processes and logging.
2. Update README/AGENTS with the new asynchronous workflow expectations.
3. Modify host Codex SOP (AGENTS.md) to always:
   - Return immediately after worker launch.
   - Rely on the status script instead of blocking commands.
4. Add documentation about approval-free container operations and command batching to minimize user prompts.

By making worker launches asynchronous, tracking them centrally, and reducing the number of host approvals, we can hit the user’s desired experience: rapid host responses, fewer confirmations, and reliable status on demand.
