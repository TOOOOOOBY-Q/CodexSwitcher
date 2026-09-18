# Maintenance synchronization — 2026-09-18

The maintainer debugged and recompiled the local Router. This update publishes that source and the exact executable from `_internal/bin/CodexSwitcherRouter.exe`; it does not replace the maintainer's fix with the earlier candidate.

The change filters Kimi's unsupported built-in `tool_search` while keeping web search and other tools. A matching forced `tool_choice` becomes `auto`.

Pre-publication checks use the existing Go tests and Windows PowerShell 5.1 smoke suite in isolated temporary homes and ports. They do not close the real Desktop, change the user's Junction, or call paid APIs. The packaged test executable is rebuilt from the maintained source.

Previous candidate verification established six models in `codex debug models` and CLI `/model`, plus real DeepSeek streaming and native apply_patch. This synchronization does not independently certify Desktop picker behavior or Kimi live calls. The maintainer's debugging report is distinct from these recorded automated checks.

The download includes the Router and test executables, so users need no Go runtime. Source checkouts can build them with `_internal/tools/Build-Router.ps1`.

Local historical reports, backups, logs, environment data, and unrelated project archives are excluded from publication.
