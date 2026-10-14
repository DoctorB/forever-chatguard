# Changelog

All notable changes to Forever ChatGuard. Versions follow `MAJOR.MINOR.PATCH`;
pre-releases carry an explicit `-alpha.N` / `-beta.N` suffix.

## 0.1.0-alpha.1 - unreleased prototype

**Integration not verified on the WoW Forever client.** Not published.

- Deterministic local engine: per-channel duplicate windows, optional burst
  limit, literal player terms, local allow and block lists, fixed rule priority.
- Observe mode on first start; nothing is hidden until filter mode is enabled
  on a client whose chat filter has been verified.
- Session quarantine with reasons, local text view and "allow author".
- Validated settings with sequential migrations; newer schemas are never
  overwritten; chat text is never written to disk.
- Fail-open behaviour and a circuit breaker after repeated internal errors.
- English and Italian interface with English fallback.
- `/fcg` commands and a basic settings panel.
