# Changelog

Notable changes, newest first. Versions follow [semantic versioning](https://semver.org).

## 1.3.0 (2026-09-09)

The notch moves the way it always looked like it should, it stops hiding inside the
camera housing on a MacBook that has one, and the window says which build of it you
are running.

### The notch

- **The top edge no longer disappears into a MacBook's camera housing.** The housing is
  not a dim or clipped piece of screen, it is not screen at all, so everything drawn
  under it was simply absent: folded, the notch was sized to the housing exactly and so
  could not be seen or found at all, and open, the camera swallowed the rings and the
  top of the grip and left a sliver of them showing underneath. The window still reaches
  the physical top of the screen, because that is what merges it with the hardware, but
  it is now deeper than the housing by as much as it needs, and the rings, the numbers,
  the grip and the folded handle's pill all sit below it. Every other edge, and every
  display without a housing, is exactly as it was.
- **Opening is one motion rather than three.** The notch used to swap its whole contents
  the instant it opened and then resize around them, so the expanded layout spent the
  entire animation being squeezed into a window far too small for it and sprang out at
  the end. Nothing is swapped now. The silhouette is drawn to whatever size the notch
  currently is, and the contents are laid out once at their full size and pinned to the
  screen edge, so the notch growing *uncovers* them instead of compressing them.
- **The rings, the grip and the button all arrive**, as one wave out of the screen edge,
  counted from the end the notch is anchored to. Only the rings animated before and
  everything else snapped in, which is what made an opening notch look half-finished.
- **Folding away is animated too**, and deliberately not the opening in reverse. The
  contents leave quickly and all together, because a staggered exit reads as hesitation
  and they have to be gone before the edge slides back across them.
- **The resize can be interrupted.** It runs on the display's own clock rather than as a
  queued window animation, so a pointer that arrives and leaves again quickly no longer
  plays two resizes back to back with the notch stuttering between the two sizes.

### The usage card

- **The card grows out of the notch.** It used to appear whole, at full size, a fixed gap
  from a ring, with nothing tying it to the notch it had come from. It now scales up from
  the side facing the notch, starting a little way inside it, and retracts the same way
  rather than being pulled out from under the pointer.
- **Moving between rings slides the card across** instead of teleporting it.
- Its shadow is drawn by the card now rather than by the window around it. A window
  shadow is fixed to the window's shape and is not redrawn as the contents change, so it
  sat at the size of the finished card while the card was still growing into it.

Reduced Motion switches all of this off, as it did before.

### Window

- **The foot of the sidebar says which build is running**: the version, and the minute
  that build was made. The version on its own does not tell two builds of one release
  apart, which is the question it is there to answer. It can be selected and copied,
  since it is the first thing an issue asks for.

## 1.2.0 (2026-09-09)

A fourth tool to read, a Claude login that repairs itself, and the first-run screen
saying what each tool actually asks of you.

### Perplexity

- **Perplexity is now one of the tools Brim can read**, from the preferences its Mac app
  already writes. No API key, no second login, and nothing read until Connect is pressed
  on that row, the same as every other tool here.
- **A count, not a ring.** Perplexity reports how many goes are left and never how many
  there were, and that allowance is nowhere on the Mac. So the notch shows the number
  itself, beside a ring left unfilled, and the card reads "4 left". Choosing a
  denominator would have meant inventing the one figure Perplexity declines to give.
- A mode Perplexity marks unavailable reads as *Unavailable*, not as zero. The file
  reports "never on your plan" and "you have used the last one" identically, so neither
  claim gets made.
- No usage deep link, because none has been verified. The link is hidden rather than
  pointed at a page that might not exist, and the counts are in Brim either way.

### Claude

- **A renewed Claude login is picked up in seconds rather than at the end of a backoff.**
  When a live read fails, retries back off by doubling, up to half an hour — so signing
  in again left an orange row on screen long after the credential behind it was valid.
  Brim now watches for Claude Code writing a new login, which it can see without reading
  the login itself, and tries again the moment one appears. The renewal logic has tests;
  the end-to-end recovery has not been watched happen, because provoking it needs a
  genuinely expired credential.
- **The lapsed-login message names the thing that fixes it** — running the `claude`
  command once — instead of promising that live usage resumes on its own. It does resume
  on its own, but only after Claude Code has been used, and the old wording sent people
  away to wait for something nothing had triggered.

### First run

- **The keychain approval is shown before it appears**, drawn at the size and wording
  macOS uses, so the box is recognised rather than met cold. The useful button is not
  the default one, and someone seeing it for the first time reads Deny as the safe
  answer and ends up with an app that never reads anything.
- Each detected tool now says what switching it on actually does. Only Claude Code
  raises a permission box; ChatGPT, Codex and Perplexity are read from files they
  already keep, and saying so stops the other two looking like they need approving.

### Window

- **Open at login shows as on, because it is.** The switch read `SMAppService`'s status,
  which on a fresh install is "not registered yet" until the app has registered itself,
  so a setting that was on and about to be acted on appeared off. It now shows the
  decision Brim actually stores. macOS holding Brim off still says so, beside the switch.
- The sidebar runs Notch, Connections, Usage, Time, Roadmap, and the window opens on
  Notch rather than on whatever was selected last.

## 1.1.0 (2026-09-09)

Where the week went, a notch sized to the screen it is on, and two things that were
quietly wrong.

### Time

- **A month of days, and how long each tool was actually used on each of them.** The
  rings answer how much of an allowance is left; they cannot answer where the week
  went, and that question has a different source: the session transcripts Claude Code
  and Codex already write on this Mac, not the providers.
- **Only the timestamps are read.** The scan looks for `"timestamp":"` and takes the
  nineteen bytes after it, walking bytes rather than decoding JSON, so there is nowhere
  a prompt, an answer or a file path could land even by accident.
- Off until it is asked for. Connecting Claude Code was permission to read a usage
  figure, not permission to walk its transcripts, so this asks separately and reads
  nothing until it is on. Turning it off deletes what the scan built.
- Time at the desk, not a file left open: runs are stitched per transcript with an idle
  cap, and two sessions running at once are counted once without being merged into one.
- Claude and ChatGPT in a browser leave nothing on this Mac to time, so the page says
  they are absent rather than drawing them as zero.

### On screen

- **One size control for the whole notch**, from 80% to 150% in steps of 5%. A notch
  drawn for a 13-inch laptop is a speck on a 32-inch display, and one drawn for the
  display takes most of a laptop's short edge.
- One factor rather than a control per dimension: the notch was drawn to proportions
  that hold together, so it resizes rather than rearranges. The screen preview in
  Settings scales with it.

### Fixed

- **A failed live Claude read no longer reports itself as connected.** The Connections
  row said "Signed in, showing Claude Code's cached reading" with a green tick while
  the panel below it said, in orange, that the saved login had lapsed. First run had it
  worst: it shows that row with nothing beneath it to contradict, so a lapsed login
  looked like plain success.
- **Opening at login is re-asserted on every launch.** It was registered once, on the
  first run, and never looked at again, so a registration that failed that day was
  never retried and one made from a copy of Brim that has since moved pointed at a
  bundle macOS could no longer find. Either way the menu bar came up empty after a
  restart. Turning the switch off in Settings is still remembered, and Brim being
  switched off by hand in System Settings is left alone and reported rather than
  fought.

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
