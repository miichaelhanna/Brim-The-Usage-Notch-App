import Foundation

enum AppPaths {
    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Brim", isDirectory: true)
    }
    /// User-added tool descriptions. One `.json` file per tool. See Docs/add-a-tool.md.
    static var tools: URL { support.appendingPathComponent("tools", isDirectory: true) }
    /// Claude Code's own config, which carries the usage cache this app reads.
    static var claudeConfig: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }
    static func prepare() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    /// Creates the tools folder, and seeds it with an example and a short readme the
    /// first time. An empty folder opened from a button explains nothing.
    static func prepareTools() throws {
        try prepare()
        let manager = FileManager.default
        try manager.createDirectory(at: tools, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        // Seed an empty folder, not merely a new one: the folder can exist without
        // ever having been seeded. Anything already in there is left alone, so a
        // sample someone deleted on purpose stays deleted.
        let existing = (try? manager.contentsOfDirectory(atPath: tools.path)) ?? []
        guard existing.filter({ !$0.hasPrefix(".") }).isEmpty else { return }
        // Not `.json`: anything with that extension is loaded as a real tool, and a
        // sample that fails to load would be the first thing anyone sees.
        try? Data(ToolSamples.example.utf8)
            .write(to: tools.appendingPathComponent("example.json.sample"))
        try? Data(ToolSamples.readme.utf8).write(to: tools.appendingPathComponent("README.md"))
    }
}

enum ToolSamples {
    /// A prompt to hand to whichever AI the person already has open.
    ///
    /// Describing a tool is easy once you know the format, and finding where a tool
    /// hides its usage is tedious, which is exactly the split a coding assistant is
    /// good at. So rather than explaining the format in the UI and hoping, the app
    /// hands over a prompt that carries the whole specification, including the rules
    /// that keep a reading honest. It has to be self-contained: the assistant reading
    /// it cannot be assumed to have the docs, or a network.
    static let aiPrompt = """
    I use Brim, a macOS app that shows my AI usage limits on a screen edge. It can \
    track any tool that writes its usage to a local JSON file, by reading a small \
    description file. No code is needed.

    Please write one for: <NAME THE TOOL HERE>

    STEP 1. Find where that tool keeps its usage on this Mac.
    Look under ~/Library/Application Support/, ~/.config/, and any dot-directory it \
    owns in my home folder, for a JSON file holding a quota, a limit, a percentage, a \
    reset time or a credit balance. Show me the file and the relevant keys before you \
    write anything.

    STEP 2. Write the description to:
    ~/Library/Application Support/Brim/tools/<id>.json

    The format, in full:
    {
      "id": "example",
      "name": "Example",
      "detect": ["/Applications/Example.app"],
      "file": "~/.example/usage.json",
      "note": "Optional. Say what this figure does NOT cover.",
      "windows": [
        { "title": "Weekly limit", "usedPercent": "quota.percent", "resetsAt": "quota.resets_at" }
      ]
    }

    - "id": lowercase letters, digits, - or _, at most 40 characters.
    - "detect": optional paths that prove the tool is installed. Omit to always show it.
    - "file": the file the tool already writes. "~" is allowed.
    - "windows": at most 6. Each needs a percentage, one of two ways:
        "usedPercent": "quota.percent"
      or a count and a cap:
        "used": "n.used", "limit": "n.limit"
      If the tool reports what is LEFT rather than what is spent, add "isRemaining": true.
    - "resetsAt": epoch seconds or an ISO 8601 timestamp. Optional.

    Paths into the file are dotted, with array indexing: usage.limits[0].percent
    That is the entire syntax. No wildcards, no filters, no expressions.

    RULES THAT MATTER, please keep these, they are the point of the app:
    - A missing field is unknown, not zero. If a value cannot be found, leave that \
      window out entirely rather than defaulting it to 0.
    - Never present one product's metering as another's. If the file holds API credits \
      and the tool also sells a subscription, name the window for what it actually \
      measures and use "note" to say what it excludes.
    - A description can only read one local JSON file. It cannot run a command or make \
      a request, so do not try to make it do either.

    STEP 3. Tell me the path you wrote and which field you mapped to each window. \
    Brim picks the file up within a few seconds. If it rejects the file, Brim's \
    Connections screen names it and says why.
    """

    static let example = """
    {
      "id": "example",
      "name": "Example",
      "file": "~/.example/usage.json",
      "windows": [
        { "title": "Monthly", "used": "requests.used", "limit": "requests.limit" }
      ]
    }
    """

    static let readme = """
    # Tools you added

    Drop a `.json` file in this folder to track a tool Brim doesn't know about.
    It needs to name a file the tool already writes, and the paths to the numbers
    inside it. No code, and no typing usage figures in by hand.

    Rename `example.json.sample` to `something.json` and edit it to start.

    A description can read one local JSON file and nothing else: it cannot run a
    command, make a network request, or read a credential. Its numbers are only ever
    shown on this Mac.

    Full format: \(Links.addATool.absoluteString)
    """
}
