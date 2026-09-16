# Changelog

## 1.0.0

- Four daily entry points: status, OpenAI switch, DeepSeek switch and force close.
- Automatically resolve the current Windows user profile.
- Switch only the verified top-level Junction; leave nested plugin links alone.
- Close Codex and Microsoft Edge with bounded retries.
- Preserve both environments and attempt a single rollback after link-creation failure.
- Discover Desktop startup from its registered MSIX package.
- Include seven isolated smoke checks.
- Exclude workstation archives, authentication data, logs and audit history from distribution.

The maintainer reported successful real-workstation acceptance of the local final implementation. The distributable uses the same implementation with user-profile portability changes; its isolated checks are recorded separately from that acceptance.
