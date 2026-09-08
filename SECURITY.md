# Security

This app reads AI account data. That deserves a threat model, not reassurance.

## Reporting a vulnerability

Open a [private security advisory](../../security/advisories/new) on this repository.
Please don't open a public issue for anything exploitable.

There is no bounty. Expect a reply within a week.

## What the app actually does

The whole attack surface, in one list:

| It does | It does not |
|---|---|
| Read `~/.claude.json` | Read conversation content, prompts or transcripts |
| Read Claude Code's Keychain item, and delete the one an earlier build of this app stored | Write to any other app's Keychain item |
| One HTTPS request to `api.anthropic.com` | Contact any other host, ever |
| Launch the `codex` and `claude` binaries, after verifying each one's signature | Run shell, evaluate strings, load plugins, or run unsigned code |
| Write to its own Application Support folder | Run a server, listen on a port, or accept input from the network |
| Undo, once, the `statusLine` an earlier build wrote into `~/.claude/settings.json` | Write to any other app's files after that |

There is no backend belonging to this project. No analytics, no telemetry, no crash
reporting, no accounts. Nothing to breach, because nothing is collected.

## Can the project be compromised?

**Dependencies: none.** Not "few". Zero. `Package.swift` declares no external
packages, so there is no npm/SwiftPM supply chain to poison. This removes the single
most common way open-source projects get compromised, and CI now fails if a dependency
is ever added.

The provider icons are the one thing sourced externally, and they are not a runtime
dependency: the outlines were converted to plain path data once and are compiled in, so
nothing is fetched at build or run time.

**CI holds no secrets.** The build-and-test workflow needs no credentials. Signing and
notarisation happen on a maintainer's machine, so no Developer ID certificate or Apple
password ever reaches a CI runner.

**The realistic risk is account takeover**, someone getting into the GitHub account
and publishing a malicious release. Mitigations: 2FA on the account, protected `main`,
and releases signed with a Developer ID that an attacker would not have.

## Can users be compromised?

**By a tampered download.** The most realistic attack is someone distributing a
modified build under this name. Official releases are signed and notarised by Apple, so
macOS verifies them before they run. **Only install from this repository's Releases
page.** If macOS warns that a build is unsigned or from an unidentified developer, that
build did not come from here.

**By the app leaking a credential.** It holds one: your Claude token, in the Keychain.
It is sent to exactly one host, and that host is the one that issued it. There is no
code path that transmits it anywhere else, and no telemetry that could carry it
accidentally.

**By a malicious `codex` or `claude` binary.** The app launches the `codex` executable
to ask it for usage, a deliberate choice, since it means this app never handles an
OpenAI credential, and the `claude` executable to ask whether you are signed in. Both
mean running code it did not build.

Some of the locations searched (`/usr/local/bin`, `~/.local/bin`, `/opt/homebrew/bin`)
are writable without administrator rights. So **the code signature of either binary is
verified before it is launched**, and it must chain to an Apple-issued identity. Real
builds from OpenAI and Anthropic are Developer ID signed and pass; an unsigned or
ad-hoc-signed file planted under the right
name is refused, with an error rather than silence. The check is repeated for a path you
choose yourself, because that skips discovery.

This is not absolute, and a signed-but-malicious binary would still pass, but it raises
the bar from "any file with the right name" to "signed with an identity Apple issued
and has not revoked". You can also turn the Codex connection off entirely.

**By a tool description someone sent you.** A description
([Docs/add-a-tool.md](Docs/add-a-tool.md)) says which local JSON file to read and where
the numbers are inside it. That is the whole vocabulary: it cannot run a command, make
a request, or read a credential, and there is no expression language for anything to
hide in. It *can* name any file your own account can read, and show numbers from it,
nothing is transmitted, but a description from someone else is still worth opening in a
text editor first. It is a few lines long.

**By the app reading Claude Code's login.** Live usage needs a credential, and the only
one that can read Anthropic's usage endpoint is the login Claude Code already stores.
Brim reads it, never writes it, and sends it only to the host that issued it. macOS
prompts before the first read and you can refuse; refusing costs you live numbers and
nothing else. Earlier builds instead kept a token of their own from `claude setup-token`
that token was always refused by the endpoint for lack of the `user:profile` scope,
and any left in your Keychain is deleted on launch.

**By hostile data in something it reads.** Everything read from another app's storage
is treated as untrusted: JSON is parsed with `JSONSerialization` rather than evaluated,
and every value is checked for shape before it is used. Nothing read from another app
is evaluated, and nothing is written back.

## What the app deliberately will not do

- **Never refresh or rewrite another app's credential.** Brim reads Claude
  Code's login at most; it cannot expire, rotate or invalidate it, so it cannot sign
  you out of Claude Code.
- **Never modify another app's configuration.** An earlier version wrapped the
  `statusLine` command in `~/.claude/settings.json`. That was intrusive and has been
  removed; the app now detects and undoes it.
- **Never invent a number.** Unrelated to security, but the same principle: the app
  says what it doesn't know instead of filling the gap.

## Verifying it yourself

The credential handling is about 100 lines, in
[`ClaudeCredential.swift`](Sources/Brim/ClaudeCredential.swift) and
[`ClaudeTokenStore.swift`](Sources/Brim/ClaudeTokenStore.swift). The single
network call is in
[`ClaudeLiveConnection.swift`](Sources/Brim/ClaudeLiveConnection.swift).

```bash
# every outbound host referenced anywhere in the source
grep -rIoE 'https?://[a-zA-Z0-9.-]+' Sources | sort -u
```

At the time of writing it returns exactly seven hosts:

| Host | Why |
|---|---|
| `api.anthropic.com` | **The only host the app contacts.** Your Claude usage. |
| `claude.ai`, `chatgpt.com` | Account pages *opened in your browser or the provider's desktop app* when you ask for a provider's own usage page. The app never requests these itself. |
| `github.com` | This repository, opened in your browser from the Add a tool card. |
| `learn.chatgpt.com`, `simpleicons.org` | Documentation links in source comments. Not requests. |

Anything else appearing in that list is a bug worth reporting.
