# Next-Version Focus Areas

Recent smoke tests confirmed the new asynchronous worker flow works end-to-end, but they also exposed a few remaining gaps that we should tackle next:

## 1. Raise Codex Shell Timeouts
- **Finding**: `codex exec` still kills long-running commands (e.g., `npm install`) after ~10 seconds, forcing the worker to retry repeatedly and slowing progress.
- **Plan**: Investigate the correct configuration flag/env var to increase the shell timeout for worker sessions, or wrap known long commands (`npm install`, `pnpm install`) in a helper that uses GNU `timeout` on our side so the command is retried outside Codex’s 10s window. Document the final approach so prompts can mention “use `npm-install.sh`” instead of raw `npm install`.

## 2. Make npm Installs Reliable
- **Finding**: Even when the container has outbound access, workers occasionally hit transient `EAI_AGAIN` errors and give up, leaving `node_modules` missing.
- **Plan**: Cache the required packages (express/nodemon) under `workspace-projects/.npm-cache` and mount it via `npm config set cache ...`, or add a helper script that runs the install with automatic retries before the worker starts. Fallback instructions should be added to README so users know how to rerun installs manually if the worker still reports network issues.

## 3. Improve Workspace Git Context
- **Finding**: The `workspace-projects/` folder is intentionally gitignored, so the worker’s `git status` output is always empty, which confused the agent and required explanations.
- **Plan**: After cloning, run `git config --global --add safe.directory /workspace/workspace-projects/*` and consider initializing a lightweight git repo per workspace (e.g., `git init --initial-branch=worker`) so status/diff commands operate locally. Update docs/prompts to mention the repo is ignored upstream and the worker should rely on local git rather than trying to add files to the host repo.

Addressing these three items will remove the remaining friction before the next human smoke test: commands won’t time out mid-install, dependencies will materialize reliably, and worker summaries will include meaningful git output.
