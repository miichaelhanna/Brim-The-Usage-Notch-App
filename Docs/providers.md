# Providers

What each supported tool reports, where the number comes from, and how it fails.

## Claude · Claude Code

One ring. Both draw on one subscription, so the app shows one allowance under the Claude
mark rather than the same number twice. Readings are still tracked per source
(`Provider.claude` and `Provider.claudeCode`), and `Provider.displayProvider` says which
ring a source is shown under.

**Live source.** `GET https://api.anthropic.com/api/oauth/usage`, authenticated with
Claude Code's own saved login, read from the Keychain
([`ClaudeCredential.swift`](../Sources/Brim/ClaudeCredential.swift)). Polled on the
refresh cadence, every minute while you are around and every five when idle, and again
whenever usage is put on screen.

**Scope, and why `claude setup-token` is not used.** This endpoint requires the
`user:profile` scope. A token minted by `claude setup-token` carries `user:inference`
alone, so it is answered with a 401 every time. Claude Code's own client gates its
usage fetch on the same scope, and says as much: *"env-var and setup-token sessions
default to user:inference only"*. Two builds of Brim were designed around such a token
before this was understood. Do not reintroduce it.

**Fallback source.** `cachedUsageUtilization` in `~/.claude.json`. Claude Code writes
this itself, so it needs no credential, but it refreshes rarely. Measured on a machine
in daily use with five active sessions, it was **399 hours old**. Treat it as a
last-known reading, never as current; the app always shows when it was taken.

**What's reported.** Anthropic returns several concurrent limits in `utilization.limits`:

| `kind` | Shown as |
|---|---|
| `session` | Current session |
| `weekly_all` | All models · weekly |
| `weekly_scoped` | *Model name* · weekly |

Each carries a percentage, a reset time, a severity, and an `is_active` flag marking
the limit currently biting. **The headline number follows `is_active`**, so it keeps a
fixed meaning between refreshes rather than jumping between limits.

Per-model limits appear only in `limits`. The sibling keys `seven_day_opus` and
`seven_day_sonnet` are `null` on real accounts and must not be relied on.

**Failure modes.**

| Symptom | Meaning |
|---|---|
| "Cached" | Brim has not been allowed to read Claude Code's login yet. Turn on live updates in Connections and choose Always Allow. |
| "Brim wasn't allowed to read…" | The Keychain prompt was declined. Try again, or allow Brim in Keychain Access. |
| "Claude Code's saved login has lapsed" | It renews the next time Claude Code is used, and live usage resumes on its own. |
| "Anthropic rejected Claude Code's saved login" | Sign in again with Claude Code. |
| "No limits reported" | The account genuinely has none. Not an error. |

## ChatGPT · Codex

One ring, for the same reason: Codex meters the ChatGPT Work allowance, so the two
would always agree.

**Model-scoped limits.** Alongside the account's own `codex` bucket, the reply carries
siblings keyed `codex_*` with a `limitName`, such as `codex_bengalfox` named
"GPT-5.3-Codex-Spark", for instance. These are limits on the same allowance, exactly as
Claude reports a per-model weekly beside its overall one, and they are read and labelled
with the model. A bucket that is *not* Codex is still refused outright: a different
metered product must never be shown as this one's usage.

**Source.** The `codex` binary bundled inside the ChatGPT app, launched as a subprocess
and spoken to over newline-delimited JSON-RPC: `initialize`, then `account/read` for
sign-in and `account/rateLimits/read` for usage. It also pushes
`account/rateLimits/updated` when limits change.

Brim never reads or holds an OpenAI credential. It asks the vendor's own binary,
which already has one. That is deliberate, and preferable to reading `~/.codex/auth.json`
and calling the backend directly.

**Scope warning.** The figure is the **Work** allowance, shared with Codex. It is *not*
regular ChatGPT Chat or Voice usage, which has no local source. The app labels this
everywhere it appears; please keep that if you touch this code.

**Failure modes.** Sign-in and usage are requested separately, so a usage failure never
gets misread as a sign-out. Requests carry a 20-second timeout and a generation guard,
so a reply from a killed process cannot alter state.

## Perplexity

**A count, not a ring.** Perplexity reports how many goes are left in each mode and
never how many there were. The allowance is not in the file, not in the app's caches,
not in its group containers, and not in its cached models config — it is simply not on
the machine. So this provider produces `UsageCount` values rather than `UsageWindow`s,
and the interface shows "4 left" beside an unfilled ring instead of a percentage.

Please keep it that way. Picking a denominator — the published free-tier figure, a
high-water mark of what has been observed — would mean inventing the one number
Perplexity declines to give, and every other reading in this app would then be sitting
next to a guess.

**Source.** `~/Library/Preferences/ai.perplexity.macv3.plist`, key `remainingUsage`.
It is a binary plist whose value is a *string* of JSON, so it decodes twice: once as a
plist, once as JSON out of that string. This is why Perplexity cannot be a described
tool (see [add-a-tool.md](add-a-tool.md)) — a descriptor reads one local JSON file, and
this is neither JSON nor singly encoded.

```json
{"modes":{"pro_search":{"available":true,"remaining_detail":{"remaining":4,"kind":"exact"}}},
 "free_queries":{"remaining_detail":{"kind":"not_provided"},"available":true}}
```

`kind` is the field that matters: only `exact` carries a number, and anything else means
Perplexity is not saying, so that mode is left out rather than shown as none left.

**Unavailable is not zero.** A mode with `available: false` gets no number. Perplexity
reports "never on your plan" and "you have just used the last one" identically, both as
an unavailable zero, so neither claim is made.

**Staleness.** macOS buffers preference writes in `cfprefsd`, so the file can trail the
running app by up to a flush. The snapshot therefore carries the file's own modification
date, never the time it was read, and a reading a few minutes old says so.

**No usage link.** Perplexity's app registers a scheme, but no destination that lands on
usage has been verified, so `desktopUsageRoute` is nil and the link is hidden. If you
verify one, that is a small and welcome pull request.

## Not yet supported

Brim lists only the tools it can read. Earlier builds also detected tools they could
not read and showed them as "not supported yet"; that list is gone from the app, and
lives here instead, as the contributions most worth making.

| Tool | What is known |
|---|---|
| **Antigravity** | Its quota lives behind gRPC/Connect calls (`RetrieveUserQuotaSummary`, `FetchQuotaStatus`) to `cloudcode-pa.googleapis.com`, with a Keychain-only credential. Reading it means protobuf framing and a credential prompt. Possible, but a project in itself. |
| **Cursor**, **Grok**, **OpenCode**, **GLM** | Unknown. If any of them keeps its usage in a local JSON file, it needs no adapter at all. Describe it (see [add-a-tool.md](add-a-tool.md)) and open a pull request with the description. These are the best first contributions. |

---

## Adding a tool without code

If the tool writes its usage to a local JSON file, it does not need an adapter at all.
it needs a description. See [add-a-tool.md](add-a-tool.md). That path covers most CLI
tools and anything Electron-based that keeps state on disk.

Write a real adapter when the usage only exists over the network, or when reading it
needs a credential or a subprocess.

## Adding a provider

1. **Find a local source.** In order of preference: a file the tool already writes
   (needs no credential), the tool's own binary asked over IPC (no credential handling),
   or an HTTP call with a credential the user explicitly grants. Never invent a number,
   and never present spend as though it were a subscription quota.

2. **Add detection** in [`ToolDetection.swift`](../Sources/Brim/ToolDetection.swift):
   a `KnownTool` case, display name, the providers it reports for, and the paths that
   prove it is installed. Detection lands together with the adapter, not before it,
   the app lists only what it can read.

3. **Parse into `UsageWindow`s.** Use `severity` and `isActive` if the provider reports
   them; set `isEstimated` if you derived rather than read the value. A missing value is
   *unknown*, not zero. Drop the window instead of reporting 0%.

4. **Respect the refresh policy.** Go through `UsageStore`'s per-provider refresh so
   your adapter inherits idle backoff and failure backoff. Don't add a timer.

5. **Test the parser** against a real captured payload, with the failure cases:
   missing fields, an empty response, and a response for a different product.

6. **Document it here**, including what it cannot report. An honest gap is worth more
   than an optimistic number.
