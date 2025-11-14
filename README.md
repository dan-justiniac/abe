# ABE, the Agent Build Environment

## Purpose
ABE provides a ready-to-use Colima VM plus an Ubuntu container so every Codex agent has a consistent workspace. Follow the steps below before attempting repo work or dependency installs.

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

## Tips
- Keep the VM running for the entire session; stopping Colima tears down `abe-dev`.
- Use bind mounts or `docker cp` to exchange files between macOS and the container.
- When in doubt, inspect logs: `colima list`, `docker logs abe-dev`, and `/Users/dan/.colima/_lima/colima/serial.log`.
