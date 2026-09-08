# Adding a tool

Brim can track any tool that writes its usage somewhere on your Mac, without
writing Swift, and without typing numbers in by hand.

You describe where the numbers live. The app reads them.

## The idea

Every automatic provider here works the same way. Claude Code writes its usage into
`~/.claude.json`; the app opens that file and pulls out a few fields. That's it. Once
you notice the shape repeats, it can be *described* rather than coded, so a tool is
added by writing a small JSON file, and adapters can be shared as files rather than as
pull requests.

## Let your AI write it

**Connections → Add a tool → Copy Prompt** puts a ready-made prompt on your clipboard.
Paste it into Claude Code, Codex, or whatever you use, name the tool, and it will hunt
for the file and write the description. The prompt carries the whole format below,
including the rules that keep a reading honest, so the assistant needs no other context.

Read what it writes before you trust the numbers. It is a few lines.

## The file

**Connections → Add a tool → Open tools folder** opens the right place, with an example
already in it. Or find it yourself:

```
~/Library/Application Support/Brim/tools/
```

Drop a `.json` file in. The app picks it up within a few seconds. No restart.

A minimal one:

```json
{
  "id": "example",
  "name": "Example",
  "file": "~/.example/usage.json",
  "windows": [
    { "title": "Monthly", "usedPercent": "quota.percent", "resetsAt": "quota.resets_at" }
  ]
}
```

| Field | Meaning |
|---|---|
| `id` | Storage key. Lowercase, no spaces. |
| `name` | What the app calls it. |
| `file` | The file the tool already writes. `~` is allowed. |
| `detect` | Optional paths proving the tool is installed. Omit to always show it. |
| `note` | Optional. Shown in the UI. The place to say what the figure excludes. |
| `windows` | The limits to read out of that file. |

## Pointing at the numbers

Paths are dotted, with array indexing:

```
usage.limits[0].percent
```

That's the whole syntax. No wildcards, no filters, no expressions. A descriptor is
something strangers share with each other, and a query language is a place for
surprises to hide.

Each window needs a percentage, one way or another:

```json
{ "title": "Session", "usedPercent": "quota.percent" }
```

or a count and a cap, which is what most tools actually report:

```json
{ "title": "Requests", "used": "n.used", "limit": "n.limit" }
```

If your tool reports what's **left** rather than what's spent, say so and the app will
invert it:

```json
{ "title": "Credits", "used": "remaining", "limit": "total", "isRemaining": true }
```

`resetsAt` accepts either epoch seconds or an ISO 8601 timestamp.

Add `detect`, a list of paths that prove the tool is installed, and the tool is
hidden on machines that don't have it. Leave it out and it always shows.

## Checking your work

Connections lists every description it loaded, and names any file it rejected along
with the reason. For the same thing in a terminal:

```
"/Applications/Brim.app/Contents/MacOS/Brim" --diagnose-tools
```

It prints each window it read and each one it dropped, which is usually enough to spot
a path that points at nothing.

## What it will not do

A descriptor can read one local JSON file. It cannot run a command, make a network
request, or read a credential. That is a deliberate limit, not an oversight: these
files get passed between people, and a descriptor must not be able to do anything a
text file couldn't.

It *can* name any file your own account can read, and show numbers from it. Nothing is
sent anywhere, and the reading only ever appears on your screen, but a description from
someone else is still worth opening in a text editor before you use it. It is four
lines; you can read the whole thing.

If a tool only exposes usage over the network, it needs a real adapter with a real
review, see [providers.md](providers.md).

## The rules still apply

- **A missing field is unknown, not zero.** A window whose fields aren't found is
  dropped rather than shown as 0%. If every window is dropped, the app says the file
  didn't contain what you described instead of inventing a reading.
- **Don't describe one product's metering as another's.** If the file holds API credits
  and the tool also sells a subscription, name the window for what it actually measures
  and use `note` to say what it excludes.

## Sharing one

If you get a tool working, open a pull request adding your file to `Descriptors/` in
this repository. That is the fastest way for the app to support more tools. You have
the tool installed and can verify the numbers, which is exactly what a maintainer
without it cannot do.
