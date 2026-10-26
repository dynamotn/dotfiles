# Crew output fixtures

Recorded or reconstructed output of each agent CLI in headless mode, read by
`dyai_crew::text` and `dyai_crew::failure` in `scripts/test/dyai_crew.bats`.

| File | Source |
|---|---|
| `claude.verdict.out`, `copilot.verdict.out` | live run on 2026-10-26, trimmed to the events the parser reads |
| `codex.blocked.err`, `gemini.blocked.*`, `opencode.blocked.out` | live failures on 2026-10-26 (401 from a local proxy, no sign-in, no provider key) |
| `gemini.verdict.out` | built from the `stream-json` events gemini-cli 0.64.0 emits (`message` deltas with `role: assistant`) |
| `opencode.verdict.out` | built from the `text` events `opencode run --format json` 1.18.31 emits |
| `codex.verdict.*`, `claude.ratelimit.out` | built from the documented formats; replace with a live capture once the agent can run |
