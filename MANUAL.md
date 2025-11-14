# Operational Manual

## Prerequisites
1. Install Colima and Docker CLI (or Docker Desktop) on macOS.
2. Install the Codex CLI (`brew install codex-cli` or grab the latest release).
3. Run `codex login` once on the host so `~/.codex` contains your credentials.

## First-Time Setup
```bash
git clone git@github.com:dan-justiniac/abe.git
cd abe
codex exec --sandbox workspace-write ./scripts/setup-platform.sh
```

The script automatically:
- Starts Colima (macOS) with 8 CPU / 24 GiB RAM / 120 GiB disk.
- Pulls `danjustiniac/abe-platform:v0.0.1`.
- Creates/starts the `abe-dev` container with your host `~/.codex` mounted read-only.
- Verifies `codex login status` inside the container.
- Writes a log to `logs/setup-<timestamp>.log`.

## Daily Workflow
1. Run the bootstrap command at the start of each session (idempotent).
2. Enter the container:
   ```bash
   docker exec -it abe-dev bash
   ```
3. Run development commands inside the shell (Node 22 + Codex CLI are preinstalled).

## Troubleshooting
- **`codex login status` fails inside container**: rerun `codex login` on the host to refresh `~/.codex`, then rerun the bootstrap script.
- **Old container/image detected**: the script automatically recreates `abe-dev`. Check `logs/setup-*.log` for details.
- **Colima not installed**: install via `brew install colima` or Docker Desktop; rerun the script.

## Maintaining the Platform Image
1. Edit `platform/Dockerfile` as needed (e.g., bump Node).
2. Build & push:
   ```bash
   docker build -t danjustiniac/abe-platform:vNEXT -f platform/Dockerfile platform
   docker push danjustiniac/abe-platform:vNEXT
   ```
3. Update `scripts/setup-platform.sh`, `README.md`, and this manual with the new tag.
4. Commit & push changes.

## Verification Commands
```bash
colima status
docker ps
docker exec abe-dev bash -lc 'node -v && npm -v'
docker exec abe-dev bash -lc 'codex login status'
```

## Support
- Log files: `logs/setup-*.log`
- Contact: dan-justiniac on GitHub for access or issue tracking.
