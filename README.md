# ABE, the Agent Build Environment

## Purpose
ABE provides a ready-to-use Colima VM plus an Ubuntu container so every Codex agent has a consistent workspace. Follow the steps below before attempting repo work or dependency installs.

## Documentation Map
- `README.md` (this file) — canonical operational instructions (bootstrap, helper scripts, workflows).
- `AGENTS.md` — quick checklist for the top-level Codex maintaining this repo (points back to relevant sections here).
- `MANUAL.md` — human-friendly summary that links to the appropriate sections below.

## Quick Start (One Command)
Prerequisites: install Colima (macOS only), Docker CLI, and run `codex login` once on the host so `~/.codex` exists. Then, from the repo root:

```sh
git clone git@github.com:dan-justiniac/abe.git
cd abe
./scripts/setup-platform.sh
```

The script starts (or verifies) Colima, pulls the published platform image, launches the long-lived `abe-dev` container with your host Codex credentials mounted, and records logs under `logs/setup-*.log`. It bind-mounts the ABE repo (the directory that contains this README) into the container at `/workspace`, sets that as the working directory, and ends by running a non-interactive `codex exec --sandbox workspace-write --add-dir ~/.colima -- "echo …"` so you see a welcome message confirming the platform is ready. After it finishes, run `docker exec -it abe-dev bash` to enter the environment—you will land in `/workspace` with the repo ready to go, so `codex` can start working from the first prompt. Subsequent Codex sessions should include `--add-dir ~/.colima` so the agent can manage Colima (example: `codex exec --sandbox workspace-write --add-dir ~/.colima -- 'pwd'`). The script also writes `platform/state.json` with the container name, repo path, timestamp, and log file so future Codex sessions can immediately confirm that the platform is already up.

## Platform Image
- Registry tag: `danjustiniac/abe-platform:v0.0.1`.
- Contents: Ubuntu 24.04, build-essential, Node.js 22 (NodeSource), git, and global `@openai/codex`.
- Default command `sleep infinity`; all work happens via `docker exec abe-dev ...`.

## Colima VM
1. Start Colima with generous resources (8 CPU / 24 GiB RAM / 120 GiB disk) and docker runtime:
   ```sh
   colima start --vm-type vz --arch aarch64 --cpu 8 --memory 24 --disk 120 --mount-type virtiofs
   ```
2. Verify the VM with `colima status` and confirm docker connectivity via `docker info`.
3. If Colima reports `Broken`, delete and recreate: `colima delete default --force` followed by the start command above.

## Docker Context
- Docker CLI is auto-pointed at the Colima socket (`unix:///Users/dan/.colima/default/docker.sock`).
- Always pull base images after Colima starts to avoid stale caches, e.g. `docker pull ubuntu:latest`.

## Long-Lived Ubuntu Container
1. Create or restart the dev container:
   ```sh
   docker run -d --name abe-dev --hostname abe-dev --restart unless-stopped ubuntu:latest sleep infinity
   ```
2. Enter the container with `docker exec -it abe-dev bash`.
3. Install tooling inside the container (apt update/upgrade, build-essential, git, pnpm, etc.) as required by the project.

## Platform Bootstrap (Manual)
The automation covers everything, but if you need to diagnose or rebuild the container manually:

```sh
docker pull danjustiniac/abe-platform:v0.0.1
docker run -d --name abe-dev --hostname abe-dev --restart unless-stopped \
  -v "$PWD:/workspace" \
  -v "$HOME/.codex:/root/.codex" \
  -w /workspace \
  danjustiniac/abe-platform:v0.0.1
```

Verify inside the container:

```sh
docker exec abe-dev bash -lc 'node -v && npm -v'   # expect v22.21.0 / npm 10.9+
docker exec abe-dev bash -lc 'codex login status'  # expect "Logged in using ChatGPT"
```

## Maintaining the Image
The source lives in `platform/Dockerfile`. To publish a new version:

```sh
docker build -t danjustiniac/abe-platform:vNEXT -f platform/Dockerfile platform
docker push danjustiniac/abe-platform:vNEXT
```

Update `scripts/setup-platform.sh` and this README with the new tag before committing.

## Helper Scripts
- `./scripts/run-in-platform.sh <cmd>` — Execute any command inside the running platform container (automatically `cd`'s to `/workspace`). Use this from the host to avoid repeating the bootstrap script; e.g. `./scripts/run-in-platform.sh ls`, `./scripts/run-in-platform.sh pnpm run lint`, or `./scripts/run-in-platform.sh codex exec --sandbox workspace-write -- 'pwd'`.
- `./scripts/launch-worker.sh [--dir relative/path] [--prompt-file file | --prompt "text"] [--timeout seconds]` — Spawn a background Codex worker in the container. The script records metadata/logs/summaries under `platform/workers/`, immediately returns with a job ID, and never asks the user to approve in-container commands. Provide the task instructions via `--prompt` or by piping a file/stdin (use `--prompt-file -`). Optional `--timeout` stops the worker if it runs too long.
- `./scripts/worker-status.sh [job-id] [--tail N | --log | --json]` — Inspect the worker registry, check whether a job is running/completed, and read the stored logs (defaults to tailing the last 20 lines when inspecting a specific job).
- `./scripts/kill-worker.sh <job-id> [--force]` — Send SIGTERM (or SIGKILL with `--force`) to a running worker and mark it as failed.
- `./scripts/collect-worker-report.sh <job-id>` — Print the worker’s prompt, summary, latest log lines, and git status/diff for the workspace.
- `./scripts/reset-platform.sh` — Clean `workspace-projects/` and `platform/workers/`, then rerun `setup-platform.sh` to start fresh before a smoke test.
- `./scripts/platform-codex.sh [--dir relative/path] [Codex args…]` — Launch a Codex session _inside_ `abe-dev`, defaulting to the repo-relative folder `workspace-projects`. Pass `--dir workspace-projects/other-repo` to target a specific checkout (the script creates the directory if it does not exist) and append any Codex flags/prompts after `--`. The script automatically ensures the container is running, `cd`s into the requested path, and starts Codex with sandbox write access so the in-platform agent can work at higher privilege.

## Working on Other Repositories
- Clone or mount external repos under `workspace-projects/` (ignored by git) so the top-level Codex keeps this repo clean while the in-platform Codex focuses on the other project.
- Use `./scripts/run-in-platform.sh 'cd workspace-projects && git clone <repo>'` (or equivalent) to prepare those directories from the host without entering the container manually.
- Launch a worker for a specific repo with `./scripts/launch-worker.sh --dir workspace-projects/<repo-name> --prompt-file instructions.txt` (or pipe the prompt via stdin). The helper records job metadata under `platform/workers/` and returns instantly with a job ID.
- Monitor or tail the worker logs any time using `./scripts/worker-status.sh <job-id>` (add `--tail 40` for longer transcripts) or `./scripts/collect-worker-report.sh <job-id>` for a full summary. Use `./scripts/kill-worker.sh <job-id>` if you need to stop a stuck worker.
- Keep this top-level Codex focused on maintaining ABE (docs, scripts, platform image). Let the in-platform Codex run the higher-privilege workflows for other repos once they live under `workspace-projects/`.

## Ideal Agent Workflow
These are the expected steps once Colima, Docker, and `codex login` prerequisites are satisfied:

1. **Start the host Codex session** — Open an interactive Codex CLI in the ABE repo root and (if needed) run `./scripts/setup-platform.sh` so `platform/state.json` reflects the current platform.
2. **Select the target repository** — Ask the user which GitHub repo to work on. Use `./scripts/run-in-platform.sh "cd workspace-projects && git clone <repo>"` (or equivalent) to ensure the repo (and any additional workspaces) live under `workspace-projects/`.
3. **Define the task** — Collaborate with the user until the scope is clear. Capture requirements in the host session so you can guide the worker agent.
4. **Prepare the workspace** — Inside `workspace-projects/<repo>`, run any bootstrapping commands (install deps, configure env files, etc.) using `./scripts/run-in-platform.sh`.
5. **Launch the worker Codex** — Run `./scripts/launch-worker.sh --dir workspace-projects/<repo> --prompt-file prompt.md --timeout 600` (or pipe the prompt via stdin). The script spawns the worker asynchronously, writes logs/summaries under `platform/workers/`, and returns immediately with a job ID so the host Codex can continue interacting with the user.
6. **Monitor & adjust** — Use `./scripts/worker-status.sh <job-id>` or `./scripts/collect-worker-report.sh <job-id>` to answer “status?” on demand. Restart/stop workers via `launch-worker.sh` or `kill-worker.sh` as needed; the host session stays free for conversation instead of blocking.
7. **Verify & report** — Once the worker reports `completed` (or `failed`), run validation commands from the host or inside the container, review diffs/tests, and summarize results plus follow-ups back to the user. Include references to worker logs or artifacts stored in `platform/workers/` when useful.

## Tips
- Keep the VM running for the entire session; stopping Colima tears down `abe-dev`.
- Use bind mounts or `docker cp` to exchange files between macOS and the container.
- When in doubt, inspect logs: `logs/setup-*.log`, `colima list`, `docker logs abe-dev`, and `/Users/dan/.colima/_lima/colima/serial.log`.
- The setup script now verifies outbound HTTPS access from inside the container. If it fails, unblock networking (e.g., ensure Colima has an Internet connection) before continuing.
- Port bindings to `0.0.0.0` are restricted inside the sandbox. When verifying servers, bind to `127.0.0.1` or rely on unit tests instead.
