# Changelog

Notable changes, newest first. Versions follow [semantic versioning](https://semver.org).

## 1.0.0 (2026-09-08)

First public release, and the first DMG meant to be installed and used.

### Usage

- **One ring per allowance.** Claude and Claude Code draw on one subscription, and
  ChatGPT and Codex on one Work allowance, so each pair is a single ring rather than
  two rings showing the same number. Each ring's detail says what it covers and what it
  leaves out.
- **The limit that is actually biting.** A provider can report several limits at once:
  a five hour session window, an all models weekly window, and per model weekly
  windows. The headline number follows whichever one the provider marks as limiting,
  and is labelled so it cannot silently change meaning between refreshes.
- **Every limit an account has**, not just the first one in the response. ChatGPT
  reports its overall limit plus model scoped ones, including a five hour window the
  overall bucket does not carry.
- **Live Claude readings** from Anthropic's usage endpoint, using the login Claude Code
  already keeps on this Mac. Brim only reads it, so it cannot expire, rotate or
  invalidate that login, and cannot sign you out of Claude Code.
- Falls back to the usage cache Claude Code keeps on disk when live updates are off,
  always shown with the age of the reading, because that cache can be days old.
- **ChatGPT and Codex** read from the ChatGPT app's own bundled engine. Brim never
  handles an OpenAI credential.
- Severity comes from the provider rather than a percentage threshold.
- Last known readings persist across launches, so the app does not open blank.

### Connecting

- **Nothing is read until you connect it.** Finding a tool on disk is a list, not
  permission. Each row has its own Connect button, that button hands you to the tool's
  own sign in, and disconnecting stops all reading.
- **Live Claude updates take one click and no token.** macOS asks once whether Brim may
  read that saved login, and the card explains why before the dialog appears.
- **Add a tool by describing it.** Any tool that writes its usage to a file on this Mac
  can be added with a small JSON description, no Swift required. Connections can copy a
  ready made prompt carrying the format and the rules that keep a reading honest, for
  pasting into whichever assistant you already use.

### On screen

- **Pick an edge** in Settings: top, right, bottom, left, or automatic. The only edge
  that cannot be chosen is the one the Dock is on, and it is shown greyed out with the
  reason rather than left out.
- **The top edge hangs from the very top of the screen**, like the hardware notch it
  imitates, and tucks into the real cutout on a Mac that has one.
- **Drag the notch** by the grip inside it, along an edge or onto another edge.
- **Hover a ring** for the full breakdown: every limit, when each resets, and when the
  reading was taken. Click a ring to refresh it.
- **The menu bar item is always there**, carrying usage, refresh, position, visibility
  and settings. A Dock icon is optional.
- Built the way a Mac app is: a source list with tinted icons, grouped forms, the
  system's own controls, and a title bar the content scrolls under.
- **Light and dark, properly.** Every colour is a system colour or a stated light and
  dark pair. The notch itself stays black in both, because it has to merge with the
  hardware.

### Privacy and security

- No analytics, no telemetry, no crash reporting, no accounts, no server, and zero
  third party dependencies.
- The only outbound host is `api.anthropic.com`, and only for usage you asked for.
- Credentials live in the macOS Keychain, and the app never writes to another tool's
  configuration.
- [SECURITY.md](SECURITY.md) documents the full attack surface and how to report a
  vulnerability. [Docs/privacy.md](Docs/privacy.md) lists what is read, file by file.

### Packaging

- Signed with a Developer ID, notarised and stapled by Apple, so the DMG opens without
  a Gatekeeper warning.
- CI builds and tests on every push, fails on any compiler warning, and holds the
  dependency count at zero. It uses no secrets: signing stays on a maintainer's machine.
