# Repository Guidelines

## Project Structure & Module Organization
- Root hosts environment docs (`README.md`) and this guide. Future source code should live under `src/`, tests in `tests/`, and automation scripts in `scripts/` (create them as work begins).
- Infrastructure assets: Colima VM config lives under `~/.colima`, while platform-specific notes belong in `docs/` once created. Keep application-level secrets in `.env.local` (gitignored) and share sanitized templates as `.env.example`.

## Build, Test, and Development Commands
- `colima start --vm-type vz --arch aarch64 --cpu 8 --memory 24 --disk 120 --mount-type virtiofs` — boots the VM with the agreed resources.
- `docker exec -it abe-dev bash` — enter the long-lived Ubuntu container where all npm/pnpm commands must run.
- Leave placeholders for future build/test scripts in `package.json`; when they exist, document them both here and in README.

## Coding Style & Naming Conventions
- Default to TypeScript/JavaScript with 2-space indentation, Prettier defaults (semi: false, singleQuote: true, trailingComma: all, printWidth: 100) as per `prettier.config.js` once added.
- Name directories and files using kebab-case (e.g., `chat-server`, `app-shell.tsx`). Environment files follow `.env.<target>`.

## Testing Guidelines
- Adopt Vitest for unit/integration coverage when code arrives. Place package-specific tests next to source (`src/foo.test.ts`) and workspace-wide fixtures in `tests/`.
- Standard command: `pnpm run test` (wraps `test:unit` and `test:integration`). Require a seeded Postgres (`just chat-db`) for integration once databases appear.

## Commit & Pull Request Guidelines
- Commit messages follow `type: summary` (e.g., `docs: record platform setup`, `feat: add chat renderer`). Keep each commit scoped and linted (`pnpm run verify`).
- P R checklist: describe intent, link issues or ADRs, attach screenshots/logs for UI or platform changes, confirm `pnpm run verify` + Codex smoke tests ran green, and note any remaining risks.

## Agent-Specific Instructions
- Always verify Colima + `abe-dev` before coding: `colima status`, `docker ps`, `docker exec abe-dev bash -lc 'codex login status'`.
- If Codex auth breaks, run `codex login` on the host, then `docker cp ~/.codex/. abe-dev:/root/.codex` to rehydrate the container. Document any new bootstrap steps immediately in README.
