# Architecture

A SwiftUI + AppKit menu-bar app built with SwiftPM. No third-party dependencies.

## Two targets

**`BrimCore`**: pure logic, no AppKit. Everything here is testable without a screen,
which is why the notch geometry, the usage model, the parsers and the refresh policy
all live in it. The test suite targets this module exclusively.

**`Brim`**: the app. AppKit panels, SwiftUI views, and everything that touches
the filesystem, the Keychain, subprocesses or the network.

The split is worth preserving. If you find yourself importing AppKit into `BrimCore`,
the logic probably wants extracting from the thing that needs AppKit instead.

## How a reading reaches the screen

```
source ──▶ connection ──▶ UsageStore ──▶ NotchPanel / DashboardView
                              │
                              └──▶ readings.json (last known)
```

- **Sources** are files, subprocesses or HTTP. See [providers.md](providers.md).
- **Connections** (`ClaudeLiveConnection`, `ClaudeUsageReader`, `CodexConnection`) each
  own one source and publish `UsageSnapshot`s through callbacks.
- **`UsageStore`** is the single observable state. It holds snapshots, decides when to
  poll, records failures, and persists last known readings.
- Views observe the store. They never fetch.

**Newest wins.** Claude has two sources that can both produce readings, so
`applyClaude` discards anything older than what is already held, so a slow live reply
cannot overwrite a newer cache read, and vice versa.

## The usage model

`UsageWindow` is one limit. Beyond the percentage it carries:

- `severity`: the provider's own judgement, which outranks any percentage ramp. A
  provider calling 84% a warning knows something a threshold doesn't.
- `isActive`: the limit currently biting. The headline number follows this so it keeps
  a fixed meaning between refreshes.
- `scopeLabel`: what the window is narrower than the plan for, e.g. a model name.
- `isEstimated`: set when a value was derived rather than reported. Anything estimated
  must say so wherever it appears.

`UsageSnapshot.updatedAt` is **when the reading was taken**, not when it was received.
A cached reading keeps its original timestamp so its true age survives.

## Refresh policy

`RefreshPolicy` (in `BrimCore`, so it is testable) decides when a provider may be
asked again:

- Normal cadence while the user is around, slower when idle.
- Exponential backoff after failures, capped.
- **Deadlines persist across launches**, so restarting cannot be used to skip a wait a
  provider asked for.

## The notch

`NotchScreenLayout` owns all geometry in AppKit screen coordinates (origin bottom-left).
It answers three questions: which edges can host the notch, where exactly the frame
goes, and what fraction along the edge a pointer maps to. It excludes the Dock's edge,
including when auto-hidden, by reading the Dock's configured orientation rather than
inferring from the visible frame.

`NotchDragSession` drives a drag. Two decisions worth knowing:

- Same-edge motion applies the gesture's **total translation to a fixed baseline**
  rather than accumulating per-event deltas, which is drift-free, and it preserves wherever
  inside the notch the grip was grabbed.
- The destination edge is the **nearest hostable one**, which makes an excluded edge
  simply unreachable rather than something to bounce off. A given pointer always
  resolves to the same edge, so hovering over an excluded strip cannot oscillate the
  notch. 28pt of hysteresis stops a corner flipping.

`NotchDragMonitor` owns the gesture **outside the view**. Changing edges replaces the
SwiftUI hosting view mid-drag, so a view-owned gesture would cancel exactly the
cross-edge drag it exists to support. The panel keeps the implicit mouse grab, so a
local event monitor still receives the events after the content view is swapped.

Mouse points come from each event's own recorded location. Reading the live pointer
inside a handler gives every queued event the final position, which makes a fast drag
read as a click.

## Two palettes

`Palette` is the app's windows, with white surfaces and a blue accent. `NotchPalette` is the
notch, which stays black whatever the app looks like, because it has to merge with the
physical notch on a MacBook.

Shared components (`UsageRing`, `UsageBar`, `QuietButton`) take a `Surface` saying
which they are being drawn on. That is passed explicitly rather than read from the
colour scheme, because the notch is dark even when the app is light. Each surface
carries its own usage ramp: the bright greens and yellows that read on black are close
to invisible on white.

## Panels

`PassivePanel` cannot become key or main, so the notch never steals focus. Visibility
mode maps to a window level: floating over apps, or just above the desktop icons.
