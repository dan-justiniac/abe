# ABE, the Agent Build Environment

## Purpose
ABE provides a ready-to-use Colima VM plus an Ubuntu container so every Codex agent has a consistent workspace. Follow the steps below before attempting repo work or dependency installs.

## Quick Start (One Command)
Prerequisites: install Colima (macOS only), Docker CLI, and run `codex login` once on the host so `~/.codex` exists. Then, from the repo root:

```sh
codex exec --sandbox workspace-write ./scripts/setup-platform.sh
```

The script starts (or verifies) Colima, pulls the published platform image, launches the long-lived `abe-dev` container with your host Codex credentials mounted, and records logs under `logs/setup-*.log`. When it finishes, run `docker exec -it abe-dev bash` to enter the environment.

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
  -v "$HOME/.codex:/root/.codex" \
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

## Tips
- Keep the VM running for the entire session; stopping Colima tears down `abe-dev`.
- Use bind mounts or `docker cp` to exchange files between macOS and the container.
- When in doubt, inspect logs: `logs/setup-*.log`, `colima list`, `docker logs abe-dev`, and `/Users/dan/.colima/_lima/colima/serial.log`.
