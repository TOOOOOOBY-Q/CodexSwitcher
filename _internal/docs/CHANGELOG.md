# Changelog

## 2.0.0 maintenance — 2026-09-18

- Synced the maintainer's local Router fix and recompiled Windows executable.
- Kimi routing removes only unsupported built-in `tool_search` definitions and resets a matching forced tool choice to `auto`; web search and agent tools remain intact.
- Added the maintained Windows x64 package under `downloads`, with a SHA256 checksum.
- Preserved the maintainer's Router source and executable; packaging does not rebuild that executable.

## 2.0.0 — 2026-09-17

- Added unified `.codex_thirdparty`; preserved OpenAI / ChatGPT environment and legacy data.
- Added Kimi Code and its four official model IDs, context and reasoning metadata.
- Added standalone Windows x64 multi-provider Responses Router with Go source and vendored TOML parser.
- Updated DeepSeek entry to V4.1 Flash / `deepseek-flash`, alongside `deepseek-v4-pro`.
- Added six-model catalog targeting native Codex model switching. CLI menu verified; Desktop acceptance is tracked separately.
- Added incremental SSE and non-stream passthrough, provider-specific key injection and local missing-key errors.
- Preserved Kimi web search and removed only built-in search definitions on DeepSeek requests.
- Added loopback-only Router startup, reuse, health, PID/path-checked shutdown and port conflict refusal.
- Added copy-based migration, staged validation, timestamped config backups and existing-home no-overwrite behavior.
- Added internal model selector with parsed TOML validation and bounded edits preserving unknown configuration.
- Archived legacy DeepSeek shortcut under `_internal/legacy`.
- Expanded isolated smoke and mock integration coverage; added real DeepSeek CLI streaming and apply_patch verification.
- Preserved existing MSIX startup, targeted process handling, Edge policy and Junction rollback.

## 1.0.0

- Four daily entry points for status, OpenAI, DeepSeek and force close.
- Verified top-level Junction replacement and rollback; preserved real environments.
- Closed Codex and Edge with bounded retries; discovered Desktop through MSIX registration.
- Seven isolated smoke checks, including valid nested Junctions.
