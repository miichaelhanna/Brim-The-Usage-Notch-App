# Contributing

## Building

Requires macOS 14+ and Swift 6.

```bash
swift build
swift test
```

`bash Scripts/build.sh` produces a signed app in `dist/`. Without a Developer ID
certificate it falls back to ad-hoc signing, which is fine for local use.

## Try it before you change it

[Download a build](../../releases), connect your own accounts, and check the numbers
against what your providers report. The diagnostic flags (`--diagnose-claude`,
`--diagnose-tools`, `--diagnose-screen`) print exactly what the app can see and expose
no credentials, so their output belongs in an issue.

## The most useful contribution

**A provider adapter for a tool you actually use.**

Read automatically today: Claude and Claude Code (one ring), ChatGPT and Codex (one
ring). Brim lists only what it can read, so a new adapter is also a new row on the
Connections screen. Wanted: Cursor, Antigravity, Grok, OpenCode, GLM, and whatever
you use that isn't here.

Nothing in the design is specific to that list. Any tool that meters usage, whether a session
limit, a weekly quota, a credit balance, fits the same model. What it needs is someone
who has the tool installed, because an adapter can only be verified against real
responses, and that is exactly what a maintainer without that tool cannot do.

[Docs/providers.md](Docs/providers.md) has the steps.

## The rules that matter

These come from the app's whole reason to exist. Please keep them.

1. **Never invent a number.** A missing value is *unknown*, not zero. Drop the window
   rather than reporting 0%.
2. **Never present one product's metering as another's.** API spend is not a
   subscription quota. ChatGPT Work is not ChatGPT Chat.
3. **Say when a reading was taken.** A cached value keeps its original timestamp. Never
   restamp a copied reading as fresh.
4. **Label anything estimated**, wherever it appears.
5. **Don't write to another app's files.** Reading what a tool already saved is the
   deal; modifying its configuration is not.
6. **Credentials go in the Keychain**, are read-only unless the user explicitly granted
   otherwise, and are sent only to the service that issued them.

## Code style

Match what's there. Specifically:

- `BrimCore` stays free of AppKit. Logic that needs a screen belongs in `Brim`.
- Comments explain *why*, not *what*. If a line looks wrong but is deliberate, the
  comment should say what breaks without it.
- New logic in `BrimCore` comes with tests. Cover the failure cases, not just the
  happy path. Missing fields, empty responses, and data for the wrong product are
  where the real bugs are.

## Reporting a bug

`--diagnose-claude` prints exactly what the app can see for Claude and why, without
exposing any credential. Its output is safe to paste into an issue.
