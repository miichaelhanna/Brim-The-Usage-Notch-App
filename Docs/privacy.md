# Privacy

Brim reads AI account data. That deserves a precise answer, not a reassuring
one. This document lists every file it touches and every request it makes.

If anything here is wrong, that's a bug. Please open an issue.

## The short version

- **No analytics, telemetry, crash reporting, accounts, or server.** There is nothing
  to opt out of because there is nothing collecting.
- **One outbound request type**, to `api.anthropic.com`, for your own Claude usage.
  The one exception is Sign In for Claude on a Mac without Claude Code, which downloads
  it from Anthropic's `downloads.claude.ai`; see [Signing in for you](#signing-in-for-you).
- **No conversation content is ever read.** Not prompts, not responses, not transcripts.
  Only quota percentages and reset times.
- **Brim holds no credential of its own.** It reads the ones the tools you already use
  have saved, and only ever reads them.
- **Nothing is read until you connect that tool.** Not on launch, not on install.

## What it reads

Everything below except the last row happens only after you press Connect for that
tool, and stops the moment you disconnect it. Detection is the one thing that runs
unasked, and all it does is check whether a path exists so the tool can be offered.

| Path | Why | What is taken |
|---|---|---|
| `~/.claude.json` | Claude's usage cache | Only `cachedUsageUtilization`: percentages, reset times, severities, and the account UUID. The rest of the file, which contains project history, is not parsed. |
| Keychain `Claude Code-credentials*` | Live Claude usage | The access token, **read-only**. Never written, refreshed, or rotated. macOS asks your permission first, and you can refuse. |
| `~/.claude/.credentials.json` | Live Claude usage | The same access token, **read-only**, for the Macs where Claude Code saved it here rather than in the Keychain. Never written. |
| `/Applications/ChatGPT.app/.../codex` | Codex and ChatGPT Work usage | Launched as a subprocess and asked for rate limits. Brim never reads or holds an OpenAI credential. Its code signature is verified first. |
| `~/.local/bin/claude`, or Homebrew's copy | Whether you are signed in to Claude | Launched as a subprocess and asked `auth status`, nothing else. Its code signature is verified first. Brim never reads or copies Claude's credential store. |
| Any file named by a description in `~/Library/Application Support/Brim/tools/` | Usage for a tool you added yourself | Read as JSON, for the fields you named. Nothing is sent anywhere. |
| `~/.claude/settings.json` | **Removal only** | Older versions installed a status-line wrapper here. Current versions only read it to detect and undo that. Nothing is added. |
| Existence checks | Tool detection | Whether paths like `/Applications/ChatGPT.app` and `~/.claude.json` exist. Contents are not read by the check itself. |

## What it writes

| Path | Contents |
|---|---|
| `~/Library/Application Support/Brim/readings.json` | Last good usage readings, so the app doesn't open blank. Percentages and timestamps only. |
| `UserDefaults` for `com.michaelhanna.brim` | Which tools you connected, notch position, visibility, which providers to show, refresh backoff deadlines. |

It writes nothing outside these, and nothing into any other application's files.

## What it sends

Exactly one request, and only when live Claude updates are on:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <your token>
```

That is a request to the service that issued the token, asking for your own account's
usage. No other host is contacted. There is no backend belonging to this project.

Codex usage involves no request from Brim at all. The ChatGPT app's own engine
makes it, exactly as it does when you use Codex normally.

## On reading another app's credential

Live Claude usage needs the login Claude Code stores, because it is the only credential
Anthropic's usage endpoint accepts for this. This is worth being uncomfortable about, so:

- macOS shows you a permission prompt. It is not silent, and you can refuse.
- The credential is read, never written. The app cannot expire, rotate or invalidate
  it, so it cannot sign you out of Claude Code.
- It is queried in two phases: item *names* first, which needs no permission, then a
  read of only the few most recent matching items. It does not ask for, and could not
  obtain, your other passwords.
- There is no alternative credential. A token from `claude setup-token` carries the
  `user:inference` scope alone and this endpoint requires `user:profile`, so it is
  refused. Earlier builds of this app were wrong about that, and any token they stored
  is deleted on launch.

The relevant code is [`ClaudeCredential.swift`](../Sources/Brim/ClaudeCredential.swift)
about 100 lines. Reading it is the fastest way to verify all of the above.

## What was removed

Versions before this one installed a helper binary and wrapped the `statusLine`
command in `~/.claude/settings.json` to capture usage from terminal sessions. That was
intrusive, only worked from a terminal, and mutated a file belonging to another tool.
It is gone. The app now detects and removes it on launch, restoring your original
status line from the backup it saved.

## Signing in for you

Someone who only uses the Claude app has no sign-in Brim can read: the app keeps its
own private. **Sign In** on the Claude row fixes that without a terminal, and only when
pressed:

1. If no Claude Code signed by Anthropic is installed, Brim downloads the latest build
   from `downloads.claude.ai`, the same files Anthropic's own installer fetches. It is
   run only if its SHA-256 matches Anthropic's published manifest **and** it is signed
   by Anthropic's Developer ID team (`Q6L2SF6YDW`). It then installs itself into
   `~/.local`, as it would from the installer. No admin rights, no script, no shell.
2. Brim runs Claude Code's own `claude auth login`, which opens claude.ai in your
   browser. Your password is typed there, never into Brim.
3. The sign-in lands in Claude Code's Keychain entry, and is read from there exactly as
   in the table above. Brim still stores no credential of its own.

Brim never signs in to Anthropic by itself and never touches the Claude app's sign-in.

