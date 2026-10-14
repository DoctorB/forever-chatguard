# Forever ChatGuard: development instructions

Spec: `docs/FOREVER_CHATGUARD_CLAUDE_CODE_SPEC.md` (binding). Target is **only**
WoW Forever (client `_classic_beta_`, build 1.60.1.x); never assume Retail,
Classic Era or Hardcore APIs.

## Layout

- `ForeverChatGuard/` is the installable addon (exactly what ships).
  `Core/` never touches client globals; `Adapters/Forever.lua` holds every
  client-specific call; `UI/` uses only `Config.Store` to change settings.
- `tests/` offline Lua 5.1 suites (`runner.lua`), benchmark (`bench.lua`),
  release tooling tests (`test_release.py`).
- `tools/ForeverChatGuardProbe/` in-game capability probe (never packaged).
- `scripts/release.py` package/gate/upload; `scripts/check_attribution.py`.

## Rules

- Lua 5.1 subset only; no `goto`, `//`, bitwise operators, `require`, `io`, `os`.
- No new globals besides `ForeverChatGuardDB` and the `/fcg` slash command.
- Capabilities change player-visible behaviour only when verified in game:
  keep `Adapter.COMPAT.verified` and the block in `docs/compatibility.md` in sync.
- Fail open: any error or unreadable (secret) value leaves chat unchanged.
- Run before every commit: `lua5.1 tests/runner.lua`, `lua5.1 tests/bench.lua`,
  `python -m unittest discover -s tests -p test_release.py`,
  `python scripts/check_attribution.py`.
- Commits use the repository's configured user identity only. No AI
  co-author trailers or "generated with" credits anywhere.
- Never force-push, move published tags or replace a published package.
