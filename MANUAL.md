# Operational Manual

This document is for the human operator. The README is the canonical source of truth for running and maintaining the ABE platform. Whenever the process changes, update the README first—this manual simply points you to the right sections.

## How to Use the Platform
1. **Bootstrap / Resume** — Follow `README.md` → “Quick Start (One Command)” to run `./scripts/setup-platform.sh`. The script also records state in `platform/state.json`, so you only need to rerun it when that file is missing or outdated.
2. **Work Inside the Container** — Enter `abe-dev` with `docker exec -it abe-dev bash` or run one-off commands from the host using `./scripts/run-in-platform.sh …` (`README.md` → “Helper Scripts”).
3. **Launch a Nested Codex Agent** — Use `./scripts/platform-codex.sh --dir workspace-projects/<repo>` whenever the agent inside the platform should work on another repository (`README.md` → “Working on Other Repositories”).

## Troubleshooting & Verification
- For common checks (Colima, Docker, Codex login), follow `README.md` → “Verification Commands”.
- If the setup script fails, review the log it prints (under `logs/`). The README outlines the expected remedies.

## Support & Updates
- Keep `README.md` current. Update this manual only to redirect humans toward new sections or workflows.
- Reach out to Dan (GitHub: `dan-justiniac`) for infrastructure access issues that fall outside the documented flow.
